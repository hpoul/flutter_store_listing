package design.codeux.flutter_store_listing

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.doThrow
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Runs under Robolectric for real [Intent] and `Uri` behaviour. With the
 * stubbed `android.jar` of a plain JVM test, `intent.action`, `intent.data` and
 * `intent.package` all come back null, so the assertions on them would fail
 * rather than pass vacuously — but they would be testing the stub instead of
 * the intent this plugin actually builds, which is the whole point of them.
 *
 * Pinned to SDK 34 rather than following `compileSdk`, so that a Flutter
 * upgrade bumping `compileSdk` cannot break these tests on a Robolectric
 * release that has no image for the new level yet.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
internal class FlutterStoreListingPluginTest {
    private lateinit var plugin: FlutterStoreListingPlugin
    private lateinit var activity: Activity
    private lateinit var result: MethodChannel.Result

    @Before
    fun setUp() {
        plugin = FlutterStoreListingPlugin()
        activity = mock(Activity::class.java)
        result = mock(MethodChannel.Result::class.java)
        val binding = mock(ActivityPluginBinding::class.java)
        Mockito.`when`(binding.activity).thenReturn(activity)
        plugin.onAttachedToActivity(binding)
    }

    private fun openStoreListing(
        url: String? = LISTING_URL,
        preferredPackage: String? = PLAY_STORE_PACKAGE,
    ) {
        plugin.onMethodCall(
            MethodCall(
                FlutterStoreListingPlugin.METHOD_OPEN_STORE_LISTING,
                mapOf(
                    FlutterStoreListingPlugin.ARGUMENT_URL to url,
                    FlutterStoreListingPlugin.ARGUMENT_PREFERRED_PACKAGE to preferredPackage,
                ),
            ),
            result,
        )
    }

    /** Captures every intent the plugin tried to start, in order. */
    private fun startedIntents(expected: Int): List<Intent> {
        val captor = ArgumentCaptor.forClass(Intent::class.java)
        verify(activity, times(expected)).startActivity(captor.capture())
        return captor.allValues
    }

    /** The `code` of the single `result.error` call. */
    private fun reportedErrorCode(): String {
        val code = ArgumentCaptor.forClass(String::class.java)
        val message = ArgumentCaptor.forClass(String::class.java)
        val details = ArgumentCaptor.forClass(Any::class.java)
        verify(result).error(code.capture(), message.capture(), details.capture())
        return code.value
    }

    @Test
    fun `views the listing URL in the play store app`() {
        openStoreListing()

        val intent = startedIntents(1).single()
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals(LISTING_URL, intent.data.toString())
        // The point of this whole module: `url_launcher` cannot set this.
        assertEquals(PLAY_STORE_PACKAGE, intent.`package`)
        verify(result).success(FlutterStoreListingPlugin.RESULT_STORE_APP)
    }

    @Test
    fun `retries without a package when the play store is absent`() {
        // A device with no Play Store: the package-restricted intent resolves to
        // nothing, the unrestricted one reaches a browser.
        doAnswer { invocation ->
            val intent = invocation.getArgument<Intent>(0)
            if (intent.`package` != null) {
                throw ActivityNotFoundException("no ${intent.`package`} on this device")
            }
            null
        }.`when`(activity).startActivity(any(Intent::class.java))

        openStoreListing()

        val intents = startedIntents(2)
        assertEquals(PLAY_STORE_PACKAGE, intents[0].`package`)
        // Same URL, no package: whatever handles play.google.com links.
        assertNull(intents[1].`package`)
        assertEquals(LISTING_URL, intents[1].data.toString())
        verify(result).success(FlutterStoreListingPlugin.RESULT_EXTERNAL)
    }

    @Test
    fun `reports unavailable when nothing can handle the URL`() {
        doThrow(ActivityNotFoundException("nothing handles anything"))
            .`when`(activity)
            .startActivity(any(Intent::class.java))

        openStoreListing()

        verify(result).success(FlutterStoreListingPlugin.RESULT_UNAVAILABLE)
    }

    @Test
    fun `retries when the package-restricted intent is refused`() {
        // A SecurityException rather than an ActivityNotFoundException: the
        // package resolves but its activity is not startable by this app, which
        // is reachable where `com.android.vending` is some other build's
        // package. Letting it escape would skip the unrestricted retry.
        doAnswer { invocation ->
            val intent = invocation.getArgument<Intent>(0)
            if (intent.`package` != null) {
                throw SecurityException("not exported")
            }
            null
        }.`when`(activity).startActivity(any(Intent::class.java))

        openStoreListing()

        val intents = startedIntents(2)
        assertEquals(PLAY_STORE_PACKAGE, intents[0].`package`)
        assertNull(intents[1].`package`)
        verify(result).success(FlutterStoreListingPlugin.RESULT_EXTERNAL)
    }

    @Test
    fun `skips the package attempt when none is given`() {
        openStoreListing(preferredPackage = null)

        assertNull(startedIntents(1).single().`package`)
        verify(result).success(FlutterStoreListingPlugin.RESULT_EXTERNAL)
    }

    @Test
    fun `rejects a missing URL`() {
        openStoreListing(url = null)

        verify(activity, never()).startActivity(any(Intent::class.java))
        assertEquals(FlutterStoreListingPlugin.ERROR_INVALID_ARGUMENTS, reportedErrorCode())
    }

    @Test
    fun `rejects an empty URL rather than viewing nothing`() {
        openStoreListing(url = "")

        verify(activity, never()).startActivity(any(Intent::class.java))
        assertEquals(FlutterStoreListingPlugin.ERROR_INVALID_ARGUMENTS, reportedErrorCode())
    }

    @Test
    fun `treats an empty package like no package`() {
        openStoreListing(preferredPackage = "")

        assertNull(startedIntents(1).single().`package`)
        verify(result).success(FlutterStoreListingPlugin.RESULT_EXTERNAL)
    }

    @Test
    fun `registers on the channel the Dart and iOS sides use`() {
        // The one string that has to match three implementations. Asserting the
        // constant alone would prove nothing; this proves `onAttachedToEngine`
        // registers under it.
        val messenger = mock(BinaryMessenger::class.java)
        val binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        Mockito.`when`(binding.binaryMessenger).thenReturn(messenger)

        plugin.onAttachedToEngine(binding)

        verify(messenger).setMessageHandler(
            ArgumentMatchers.eq("flutter_store_listing"),
            ArgumentMatchers.any(),
        )
    }

    @Test
    fun `reports a detached activity rather than guessing`() {
        plugin.onDetachedFromActivity()

        openStoreListing()

        verify(activity, never()).startActivity(any(Intent::class.java))
        assertEquals(FlutterStoreListingPlugin.ERROR_NO_ACTIVITY, reportedErrorCode())
    }

    @Test
    fun `does not claim methods it has no implementation for`() {
        plugin.onMethodCall(MethodCall("isSupportedRequestReview", null), result)

        verify(result).notImplemented()
    }

    private companion object {
        const val LISTING_URL = "https://play.google.com/store/apps/details?id=design.codeux.authpass"
        const val PLAY_STORE_PACKAGE = "com.android.vending"
    }
}

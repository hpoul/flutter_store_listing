package design.codeux.flutter_store_listing

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Opens a store listing with the intent Google documents, rather than handing
 * the URL to the OS and hoping.
 *
 * "Linking to Google Play" says to view the `play.google.com` listing URL with
 * the package set to `com.android.vending`, so the Play Store app handles it
 * instead of a browser or a chooser. That is the whole reason this module
 * exists: `url_launcher` cannot set a package.
 *
 * Nothing here queries for a handler. `canLaunchUrl` and the `market://` probe
 * it used to back are subject to Android 11 package visibility, so they report
 * false without a `<queries>` entry in the *consumer's* manifest; attempting
 * the intent and handling [ActivityNotFoundException] is not, which is exactly
 * what Android's package-visibility guidance recommends. So this package needs
 * no manifest entry from anybody.
 */
class FlutterStoreListingPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler {
    private var channel: MethodChannel? = null

    /**
     * Set while a host activity is attached. Starting an activity needs one:
     * launching from the application context would require
     * `FLAG_ACTIVITY_NEW_TASK` and land the listing in its own task.
     */
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            METHOD_OPEN_STORE_LISTING -> openStoreListing(call, result)
            else -> result.notImplemented()
        }
    }

    private fun openStoreListing(
        call: MethodCall,
        result: Result,
    ) {
        val url = call.argument<String>(ARGUMENT_URL)
        if (url.isNullOrEmpty()) {
            result.error(
                ERROR_INVALID_ARGUMENTS,
                "`$ARGUMENT_URL` is required and must not be empty.",
                null,
            )
            return
        }
        val host = activity
        if (host == null) {
            // Reported rather than swallowed: the Dart side can still fall back
            // to `url_launcher`, but a plugin with no attached activity is a
            // host problem worth surfacing, not a missing store.
            result.error(
                ERROR_NO_ACTIVITY,
                "No activity is attached; cannot open a store listing.",
                null,
            )
            return
        }

        // The preferred package comes from Dart so that everything Play-specific
        // stays next to the URL that is built for it.
        val preferredPackage = call.argument<String>(ARGUMENT_PREFERRED_PACKAGE)
        if (!preferredPackage.isNullOrEmpty() && startViewIntent(host, url, preferredPackage)) {
            result.success(RESULT_STORE_APP)
            return
        }
        if (startViewIntent(host, url, packageName = null)) {
            result.success(RESULT_EXTERNAL)
            return
        }
        result.success(RESULT_UNAVAILABLE)
    }

    /**
     * Views [url], restricted to [packageName] when one is given.
     *
     * Returns false when nothing on the device can handle it, which for a
     * package-restricted intent means that app is absent or disabled.
     */
    private fun startViewIntent(
        host: Activity,
        url: String,
        packageName: String?,
    ): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        if (packageName != null) {
            intent.setPackage(packageName)
        }
        return try {
            host.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    companion object {
        /** Shared with the iOS implementation and with the Dart side. */
        const val CHANNEL_NAME = "flutter_store_listing"

        const val METHOD_OPEN_STORE_LISTING = "openStoreListing"

        const val ARGUMENT_URL = "url"
        const val ARGUMENT_PREFERRED_PACKAGE = "preferredPackage"

        /** Opened in the app named by [ARGUMENT_PREFERRED_PACKAGE]. */
        const val RESULT_STORE_APP = "storeApp"

        /** Opened, but by whatever else handles the URL — typically a browser. */
        const val RESULT_EXTERNAL = "external"

        /** Nothing on the device could handle it. */
        const val RESULT_UNAVAILABLE = "unavailable"

        const val ERROR_INVALID_ARGUMENTS = "invalid_arguments"
        const val ERROR_NO_ACTIVITY = "no_activity"
    }
}

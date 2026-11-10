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
            // An error rather than an outcome, because this is a host problem
            // worth surfacing and not a missing store.
            //
            // Falling back to `url_launcher` cannot rescue it: that plugin is
            // `ActivityAware` too and is detached in the same window, so its
            // own `ensureActivity` throws. So as of 2.0 the Dart side does not
            // try. It tells `MissingPluginException` (fall back) apart from a
            // `PlatformException` like this one (do not), and reports
            // `launchRefused` directly rather than reaching the same answer by
            // way of a second failure. Up to 1.4.0 it caught
            // `PlatformException` wholesale and retried.
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
     * Returns false when the intent could not be started at all, which for a
     * package-restricted intent means that app is absent or disabled.
     *
     * A true means the system accepted the intent, not that the listing became
     * visible. Two cases report true and show the user nothing: a background
     * activity launch that the system blocks, which it only logs rather than
     * reporting back to the caller, and a *suspended* Play Store, which
     * resolves and then shows the system's own "app paused" dialog. Neither is
     * detectable from here.
     */
    @Suppress("UseKtx") // `url.toUri()` would mean depending on androidx.core.
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
        } catch (e: SecurityException) {
            // The resolved activity is not exported, or demands a permission
            // this app does not hold. A package-restricted intent can reach
            // this where `com.android.vending` is not Google's Play Store:
            // microG and Aurora-patched builds register that same package name.
            // Reported as "could not start" so the caller's unrestricted retry
            // still runs, which letting this escape would skip.
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

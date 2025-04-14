package design.codeux.flutter_store_listing;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/** FlutterStoreListingPlugin */
public class FlutterStoreListingPlugin implements FlutterPlugin, MethodCallHandler {

  private void register(BinaryMessenger binaryMessenger) {
    final MethodChannel channel = new MethodChannel(binaryMessenger, "flutter_store_listing");
    channel.setMethodCallHandler(new FlutterStoreListingPlugin());
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, Result result) {
    result.notImplemented();
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    register(binding.getBinaryMessenger());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
  }
}

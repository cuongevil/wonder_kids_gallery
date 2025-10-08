package com.ctmd.wonderforge.wonder_kids_gallery

import android.view.LayoutInflater
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ✅ Đăng ký NativeAdFactory để Flutter có thể hiển thị native ad pastel
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "listTile",
            ListTileNativeAdFactory(layoutInflater)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // ✅ Gỡ đăng ký khi Flutter engine bị destroy (tránh memory leak)
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "listTile")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/**
 * 🎨 Factory tạo quảng cáo Native theo layout pastel list_tile_native_ad.xml
 * file layout: android/app/src/main/res/layout/list_tile_native_ad.xml
 */
class ListTileNativeAdFactory(private val inflater: LayoutInflater) :
    GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {

        // Inflate layout XML
        val adView = inflater.inflate(R.layout.list_tile_native_ad, null) as NativeAdView

        // Ánh xạ các view trong layout
        val headlineView: TextView = adView.findViewById(R.id.ad_headline)
        val bodyView: TextView = adView.findViewById(R.id.ad_body)
        val iconView: ImageView = adView.findViewById(R.id.ad_icon)
        val ctaButton: Button = adView.findViewById(R.id.ad_call_to_action)
        val advertiserView: TextView = adView.findViewById(R.id.ad_advertiser)

        // Gán dữ liệu quảng cáo
        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        if (nativeAd.body == null) {
            bodyView.visibility = TextView.GONE
        } else {
            bodyView.text = nativeAd.body
            bodyView.visibility = TextView.VISIBLE
        }
        adView.bodyView = bodyView

        if (nativeAd.icon != null) {
            iconView.setImageDrawable(nativeAd.icon!!.drawable)
            iconView.visibility = ImageView.VISIBLE
        } else {
            iconView.visibility = ImageView.GONE
        }
        adView.iconView = iconView

        ctaButton.text = nativeAd.callToAction
        adView.callToActionView = ctaButton

        advertiserView.text = nativeAd.advertiser
        adView.advertiserView = advertiserView

        // Gán NativeAd cho view
        adView.setNativeAd(nativeAd)
        return adView
    }
}

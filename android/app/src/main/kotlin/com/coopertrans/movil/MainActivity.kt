package com.coopertrans.movil

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Esto asegura que todos los plugins (como Firestore) se registren 
        // correctamente en el hilo principal de la aplicaci�n.
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }
}

#!/data/data/com.termux/files/usr/bin/bash
# Creates the YESMIN AI Android project (step 1) in ~/yesmin-ai
set -e
mkdir -p ~/yesmin-ai && cd ~/yesmin-ai
mkdir -p "."
cat > "ARCHITECTURE.md" <<'YESMIN_EOF'
# YESMIN AI — Architecture

Kotlin + Jetpack Compose, single Gradle module, package-by-feature, MVVM with unidirectional state.
minSdk 26, targetSdk 35.

```
com.yesmin.ai
├─ ui/            theme, shared components, navigation, one package per screen
├─ ai/            AiBrain interface + GeminiBrain (REST, SSE streaming); later: other models
├─ voice/         SpeechInput (SpeechRecognizer), SpeechOutput (TextToSpeech), WakeWord
├─ phone/         AppLauncher, YouTube intents, YesminAccessibilityService, ActionExecutor
├─ coding/        CodeSession, prompt templates, ProjectExporter
├─ memory/        Room DB: conversations, user-approved memories
├─ settings/      DataStore prefs; API key in EncryptedSharedPreferences / Keystore
└─ tools/         Tool interface for plugins (alarm, timer, calendar, weather, translate)
```

## Key decisions
- **AiBrain interface**: GeminiBrain is one implementation, so more models plug in later.
- **Tool registry**: assistant actions (open app, set timer…) are `Tool`s the model can request;
  every sensitive tool requires an explicit user confirmation step.
- **Permissions**: asked at point of use, with an explanation screen first. Accessibility Service
  is opt-in, off by default, and can be revoked from Settings.
- **Secrets**: API key never in source or logs; HTTPS only.
- **Orb**: `AiOrb(level)` already accepts an amplitude so mic/TTS can drive it later.

## Build steps
1. Architecture + main screen (this commit)
2. Settings > AI Brain, Gemini client, streaming chat, history
3. Voice in/out, language, wake word
4. Coding mode
5. Phone control + Accessibility Service
6. Memory, reminders, alarms, calendar, weather, translation
7. Camera / image / PDF understanding
YESMIN_EOF
mkdir -p "app"
cat > "app/build.gradle.kts" <<'YESMIN_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.yesmin.ai"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.yesmin.ai"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }
    buildTypes { release { isMinifyEnabled = false } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}
dependencies {
    val bom = platform("androidx.compose:compose-bom:2024.09.00")
    implementation(bom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.navigation:navigation-compose:2.8.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.5")
    implementation("androidx.core:core-ktx:1.13.1")
}
YESMIN_EOF
mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'YESMIN_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Step 1 needs no permissions. Each later feature declares its own,
         and asks only at the moment the user opens that feature. -->
    <application
        android:allowBackup="false"
        android:label="@string/app_name"
        android:theme="@style/Theme.Yesmin">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
YESMIN_EOF
mkdir -p "app/src/main/java/com/yesmin/ai"
cat > "app/src/main/java/com/yesmin/ai/MainActivity.kt" <<'YESMIN_EOF'
package com.yesmin.ai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.yesmin.ai.ui.nav.AppNav
import com.yesmin.ai.ui.theme.YesminTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { YesminTheme { AppNav() } }
    }
}
YESMIN_EOF
mkdir -p "app/src/main/java/com/yesmin/ai/ui/components"
cat > "app/src/main/java/com/yesmin/ai/ui/components/AiOrb.kt" <<'YESMIN_EOF'
package com.yesmin.ai.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yesmin.ai.ui.theme.Yc

/** Animated core. `level` (0..1) will later be driven by real mic/TTS amplitude. */
@Composable
fun AiOrb(modifier: Modifier = Modifier, size: Dp = 240.dp, level: Float = 0f) {
    val t = rememberInfiniteTransition(label = "orb")
    val pulse by t.animateFloat(
        0.94f, 1.06f,
        infiniteRepeatable(tween(2600, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "p"
    )
    val spin by t.animateFloat(
        0f, 360f, infiniteRepeatable(tween(14000, easing = LinearEasing)), label = "s"
    )
    Box(modifier.size(size)) {
        Canvas(Modifier.size(size)) {
            val c = center
            val r = this.size.minDimension / 2f
            // outer glow
            drawCircle(
                Brush.radialGradient(
                    listOf(Yc.Violet.copy(alpha = 0.45f), Yc.Blue.copy(alpha = 0.12f), Color.Transparent),
                    c, r * 1.05f
                ), r * 1.05f, c
            )
            // core
            val cr = r * 0.52f * pulse * (1f + level * 0.25f)
            drawCircle(
                Brush.radialGradient(
                    listOf(Color.White.copy(alpha = 0.9f), Yc.Magenta, Yc.Violet, Yc.Deep),
                    Offset(c.x - cr * 0.25f, c.y - cr * 0.3f), cr * 1.4f
                ), cr, c
            )
            // rings
            val ringR = r * 0.74f
            drawArc(
                Brush.sweepGradient(listOf(Color.Transparent, Yc.Blue, Yc.Magenta, Color.Transparent), c),
                spin, 250f, false,
                Offset(c.x - ringR, c.y - ringR), Size(ringR * 2, ringR * 2),
                style = Stroke(3.dp.toPx(), cap = StrokeCap.Round)
            )
            val ring2 = r * 0.88f
            drawArc(
                Yc.Violet.copy(alpha = 0.5f), -spin * 0.6f, 120f, false,
                Offset(c.x - ring2, c.y - ring2), Size(ring2 * 2, ring2 * 2),
                style = Stroke(2.dp.toPx(), cap = StrokeCap.Round)
            )
        }
    }
}
YESMIN_EOF
mkdir -p "app/src/main/java/com/yesmin/ai/ui/components"
cat > "app/src/main/java/com/yesmin/ai/ui/components/Glass.kt" <<'YESMIN_EOF'
package com.yesmin.ai.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import com.yesmin.ai.ui.theme.Yc

/** Frosted-style tile. True blur isn't available on all API levels, so we layer translucency + edge light. */
@Composable
fun GlassTile(label: String, icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier
            .clip(shape)
            .background(Brush.verticalGradient(listOf(Yc.Glass, Color0)))
            .border(BorderStroke(1.dp, Yc.GlassEdge), shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = 16.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(icon, contentDescription = null, tint = Yc.Magenta, modifier = Modifier.size(26.dp))
        Text(label, color = Yc.Text, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

private val Color0 = androidx.compose.ui.graphics.Color(0x08FFFFFF)
YESMIN_EOF
mkdir -p "app/src/main/java/com/yesmin/ai/ui/home"
cat > "app/src/main/java/com/yesmin/ai/ui/home/HomeScreen.kt" <<'YESMIN_EOF'
package com.yesmin.ai.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yesmin.ai.ui.components.AiOrb
import com.yesmin.ai.ui.components.GlassTile
import com.yesmin.ai.ui.theme.Yc

@Composable
fun HomeScreen(onOpen: (String) -> Unit) {
    Box(
        Modifier.fillMaxSize()
            .background(Brush.verticalGradient(listOf(Yc.Void, Yc.Deep, Yc.Void)))
            .safeDrawingPadding()
    ) {
        Column(
            Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("YESMIN AI", color = Yc.Text, fontSize = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
                    Text("Your personal assistant", color = Yc.TextDim, fontSize = 12.sp)
                }
                Icon(
                    Icons.Filled.Settings, "Settings", tint = Yc.Text,
                    modifier = Modifier.size(44.dp).clip(CircleShape)
                        .clickable { onOpen("settings") }.padding(10.dp)
                )
            }

            Spacer(Modifier.weight(1f))
            AiOrb(size = 250.dp)
            Spacer(Modifier.height(20.dp))
            Text("Tap the mic to talk, or open chat.", color = Yc.TextDim, fontSize = 14.sp)
            Spacer(Modifier.weight(1f))

            // Mic: the primary action.
            Box(
                Modifier.size(76.dp).clip(CircleShape)
                    .background(Brush.linearGradient(listOf(Yc.Violet, Yc.Magenta)))
                    .border(2.dp, Yc.GlassEdge, CircleShape)
                    .clickable { onOpen("voice") },
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Filled.Mic, "Start voice", tint = Yc.Text, modifier = Modifier.size(34.dp)) }

            Spacer(Modifier.height(24.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                GlassTile("Chat", Icons.Filled.Chat, Modifier.weight(1f)) { onOpen("chat") }
                GlassTile("Coding", Icons.Filled.Code, Modifier.weight(1f)) { onOpen("coding") }
                GlassTile("Phone", Icons.Filled.PhoneAndroid, Modifier.weight(1f)) { onOpen("phone") }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}
YESMIN_EOF
mkdir -p "app/src/main/java/com/yesmin/ai/ui/nav"
cat > "app/src/main/java/com/yesmin/ai/ui/nav/AppNav.kt" <<'YESMIN_EOF'
package com.yesmin.ai.ui.nav

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.yesmin.ai.ui.home.HomeScreen
import com.yesmin.ai.ui.theme.Yc

private data class Planned(val route: String, val title: String, val step: Int, val note: String)

// Honest placeholders: each screen states it is not built yet and which step builds it.
private val planned = listOf(
    Planned("chat", "Chat", 2, "Gemini streaming chat, history, API key + connection test."),
    Planned("voice", "Voice", 3, "Speech input, female TTS, Hindi/English/Hinglish, wake word."),
    Planned("coding", "Coding mode", 4, "Code assistant, editor with highlighting, project export."),
    Planned("phone", "Phone control", 5, "App launching, YouTube, Accessibility Service with consent."),
    Planned("settings", "Settings", 2, "AI Brain section first; voice, privacy and personality follow."),
)

@Composable
fun AppNav() {
    val nav = rememberNavController()
    NavHost(nav, startDestination = "home") {
        composable("home") { HomeScreen { nav.navigate(it) } }
        planned.forEach { p ->
            composable(p.route) {
                Box(
                    Modifier.fillMaxSize().background(Yc.Void).safeDrawingPadding().padding(32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(p.title, color = Yc.Text, fontSize = 24.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("Not built yet. Planned for step ${p.step}.", color = Yc.Magenta, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(8.dp))
                        Text(p.note, color = Yc.TextDim, textAlign = TextAlign.Center)
                    }
                }
            }
        }
    }
}
YESMIN_EOF
mkdir -p "app/src/main/java/com/yesmin/ai/ui/theme"
cat > "app/src/main/java/com/yesmin/ai/ui/theme/Theme.kt" <<'YESMIN_EOF'
package com.yesmin.ai.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

object Yc {
    val Void = Color(0xFF0A0612)
    val Deep = Color(0xFF150B26)
    val Violet = Color(0xFF8B3DFF)
    val Magenta = Color(0xFFD14BFF)
    val Blue = Color(0xFF3D8BFF)
    val Glass = Color(0x1AFFFFFF)
    val GlassEdge = Color(0x33B98CFF)
    val Text = Color(0xFFF1EAFF)
    val TextDim = Color(0xFF9C8FB8)
}

@Composable
fun YesminTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Yc.Violet, secondary = Yc.Blue,
            background = Yc.Void, surface = Yc.Deep,
            onBackground = Yc.Text, onSurface = Yc.Text
        ),
        content = content
    )
}
YESMIN_EOF
mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/strings.xml" <<'YESMIN_EOF'
<resources><string name="app_name">YESMIN AI</string></resources>
YESMIN_EOF
mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/themes.xml" <<'YESMIN_EOF'
<resources>
    <style name="Theme.Yesmin" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">#0A0612</item>
        <item name="android:statusBarColor">#0A0612</item>
        <item name="android:navigationBarColor">#0A0612</item>
    </style>
</resources>
YESMIN_EOF
mkdir -p "."
cat > "build.gradle.kts" <<'YESMIN_EOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.20" apply false
}
YESMIN_EOF
mkdir -p "."
cat > "gradle.properties" <<'YESMIN_EOF'
org.gradle.jvmargs=-Xmx2g
android.useAndroidX=true
kotlin.code.style=official
YESMIN_EOF
mkdir -p "."
cat > "settings.gradle.kts" <<'YESMIN_EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "YesminAI"
include(":app")
YESMIN_EOF
echo "Done. Project created in ~/yesmin-ai"

package app.nw.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.nw.tv.model.Manga

private val Background = Color(0xFF090A0F)
private val SurfaceDark = Color(0xFF14161E)
private val SurfaceRaised = Color(0xFF1D202A)
private val Lavender = Color(0xFFB8A0FF)
private val Muted = Color(0xFFA8A8B5)

private val continueReading = listOf(
    Manga("The Summer Hikaru Died", "Chapter 18", Color(0xFF4B385F), "62%"),
    Manga("Witch Hat Atelier", "Chapter 85", Color(0xFF31556A), "24%"),
    Manga("Frieren: Beyond Journey's End", "Chapter 141", Color(0xFF46554D), "91%")
)
private val popular = listOf(
    Manga("One Piece", "Ongoing · 1,150 chapters", Color(0xFF7A4A2E)),
    Manga("Jujutsu Kaisen", "Completed · 271 chapters", Color(0xFF3C466A)),
    Manga("Blue Lock", "Ongoing · 302 chapters", Color(0xFF31566B)),
    Manga("Dandadan", "Ongoing · 190 chapters", Color(0xFF784E55)),
    Manga("Solo Leveling", "Completed · 202 chapters", Color(0xFF463E70))
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { NwApp() }
    }
}

@Composable
private fun NwApp() {
    var screen by remember { mutableStateOf("home") }
    var selected by remember { mutableStateOf<Manga?>(null) }
    var reader by remember { mutableStateOf(false) }

    MaterialTheme(colorScheme = darkColorScheme(background = Background, surface = SurfaceDark, primary = Lavender)) {
        Surface(Modifier.fillMaxSize(), color = Background) {
            when {
                reader -> ReaderScreen(onBack = { reader = false })
                selected != null -> DetailScreen(selected!!, onBack = { selected = null }, onRead = { reader = true })
                else -> HomeScreen(screen = screen, onNavigate = { screen = it }, onManga = { selected = it })
            }
        }
    }
}

@Composable
private fun HomeScreen(screen: String, onNavigate: (String) -> Unit, onManga: (Manga) -> Unit) {
    Row(Modifier.fillMaxSize()) {
        NavigationRail(selected = screen, onNavigate = onNavigate)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 30.dp, end = 54.dp, top = 34.dp, bottom = 36.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Text("Good evening", color = Muted, fontSize = 18.sp)
                    Text("Welcome back", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold)
                }
                FocusButton(label = "Search", icon = Icons.Default.Search, onClick = { onNavigate("search") })
            }
            Spacer(Modifier.height(34.dp))
            Text("Continue reading", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(14.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(18.dp), contentPadding = PaddingValues(end = 12.dp)) {
                items(continueReading) { manga -> MangaCard(manga, onClick = { onManga(manga) }, showProgress = true) }
            }
            Spacer(Modifier.height(34.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Popular this week", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                Text("Browse all  ›", color = Lavender, fontSize = 16.sp)
            }
            Spacer(Modifier.height(14.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(18.dp), contentPadding = PaddingValues(end = 12.dp)) {
                items(popular) { manga -> MangaCard(manga, onClick = { onManga(manga) }) }
            }
            Spacer(Modifier.height(34.dp))
            SyncStatus()
        }
    }
}

@Composable
private fun NavigationRail(selected: String, onNavigate: (String) -> Unit) {
    Column(Modifier.width(104.dp).fillMaxHeight().background(Color(0xFF101117)).padding(vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("N", color = Lavender, fontSize = 32.sp, fontWeight = FontWeight.Black)
        Spacer(Modifier.height(42.dp))
        listOf("home" to Icons.Default.Home, "library" to Icons.Default.Bookmark, "downloads" to Icons.Default.Download, "settings" to Icons.Default.Settings).forEach { (id, icon) ->
            NavButton(icon, id == selected, onClick = { onNavigate(id) })
            Spacer(Modifier.height(18.dp))
        }
    }
}

@Composable
private fun NavButton(icon: ImageVector, active: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Box(Modifier.size(58.dp).clip(RoundedCornerShape(18.dp)).background(if (active) Lavender.copy(alpha = .18f) else Color.Transparent).border(if (focused) 2.dp else 0.dp, Lavender, RoundedCornerShape(18.dp)).onFocusChanged { focused = it.isFocused }.focusable().clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, tint = if (active) Lavender else Muted, modifier = Modifier.size(25.dp))
    }
}

@Composable
private fun MangaCard(manga: Manga, onClick: () -> Unit, showProgress: Boolean = false) {
    var focused by remember { mutableStateOf(false) }
    Column(Modifier.width(174.dp).onFocusChanged { focused = it.isFocused }.focusable().clickable(onClick = onClick)) {
        Box(Modifier.fillMaxWidth().height(232.dp).clip(RoundedCornerShape(12.dp)).background(manga.color).border(if (focused) 3.dp else 0.dp, Lavender, RoundedCornerShape(12.dp))) {
            Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.SpaceBetween) {
                Text("MANGA", color = Color.White.copy(alpha = .65f), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                Text(manga.title, color = Color.White, fontSize = 21.sp, lineHeight = 24.sp, fontWeight = FontWeight.Bold, maxLines = 4, overflow = TextOverflow.Ellipsis)
            }
            if (showProgress) {
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(5.dp).background(Color.White.copy(alpha = .18f)))
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth(fraction = manga.progress.dropLast(1).toFloat() / 100f).height(5.dp).background(Lavender))
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(manga.title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(manga.subtitle, color = Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun SyncStatus() {
    Card(colors = CardDefaults.cardColors(containerColor = SurfaceDark), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Sync, contentDescription = null, tint = Lavender, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(14.dp))
            Column { Text("Library is up to date", color = Color.White, fontWeight = FontWeight.SemiBold); Text("Last checked 12 minutes ago", color = Muted, fontSize = 13.sp) }
        }
    }
}

@Composable
private fun FocusButton(label: String, icon: ImageVector, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    OutlinedButton(onClick = onClick, modifier = Modifier.onFocusChanged { focused = it.isFocused }.border(if (focused) 2.dp else 0.dp, Lavender, RoundedCornerShape(24.dp)), border = BorderStroke(1.dp, Color.White.copy(alpha = .22f)), contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)); Text(label)
    }
}

@Composable
private fun DetailScreen(manga: Manga, onBack: () -> Unit, onRead: () -> Unit) {
    BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(48.dp)) {
        Text("‹  Back", color = Lavender, fontSize = 18.sp, modifier = Modifier.clickable(onClick = onBack))
        Spacer(Modifier.height(28.dp))
        Row(verticalAlignment = Alignment.Top) {
            Box(Modifier.size(210.dp, 286.dp).clip(RoundedCornerShape(14.dp)).background(manga.color), contentAlignment = Alignment.BottomStart) { Text(manga.title, Modifier.padding(18.dp), color = Color.White, fontSize = 25.sp, fontWeight = FontWeight.Bold) }
            Spacer(Modifier.width(34.dp))
            Column(Modifier.width(560.dp)) {
                Text(manga.title, color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp)); Text(manga.subtitle, color = Muted, fontSize = 17.sp)
                Spacer(Modifier.height(24.dp)); Text("A comfortable, focused reading experience built for the big screen. Your library, downloads, and reading progress stay in one place.", color = Color(0xFFD0D0D8), fontSize = 17.sp, lineHeight = 26.sp)
                Spacer(Modifier.height(28.dp)); Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { Button(onClick = onRead) { Text("Read chapter") }; OutlinedButton(onClick = {}) { Text("Add to library") } }
            }
        }
    }
}

@Composable
private fun ReaderScreen(onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    Box(Modifier.fillMaxSize().background(Color(0xFF202127))) {
        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Chapter 18", color = Color.White, fontSize = 25.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(10.dp)); Text("Reader preview · use ← → to change pages", color = Muted, fontSize = 16.sp)
            Spacer(Modifier.height(28.dp)); Text("NW", color = Lavender, fontSize = 72.sp, fontWeight = FontWeight.Black)
        }
        Text("‹  Back", Modifier.align(Alignment.TopStart).padding(34.dp).clickable(onClick = onBack), color = Color.White, fontSize = 18.sp)
        Text("1 / 24", Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp), color = Muted, fontSize = 14.sp)
    }
}

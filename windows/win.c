#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <stdint.h>

#include "game.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static const unsigned BRICK_HEX[] = {
    0xF0714A, 0xF0A04A, 0xF0D15A, 0x7ED0A0, 0x7EC8F0, 0x5A88E8, 0xB48AF0,
};
static const unsigned STEEL_HEX = 0xD5DEEA;

static COLORREF rgb(unsigned hex) {
    return RGB((hex >> 16) & 255, (hex >> 8) & 255, hex & 255);
}

static int sy(double sim_y) {
    return (int)(VIEW_H - sim_y + 0.5);
}

typedef struct {
    HWND hwnd;
    Game game;
    int mouse_mode, paused, menu, muted, admin, fullscreen, can_continue;
    int menu_rank, best, shown_level, shown_bonus;
    int key_left, key_right;
    int mouse_x, mouse_y, mouse_down;
    double banner_left, notice_left, gain_left, gain_x, gain_y;
    int gain_value;
    char notice[96];
    int notice_bad;
    char banner[160];
    wchar_t stand_path[MAX_PATH];
    wchar_t best_path[MAX_PATH];
    double save_wait;
    HWAVEOUT wave;
    WAVEHDR headers[6];
    int16_t samples[6][8000];
    HFONT font_big, font_ui, font_small;
    HDC mem;
    HBITMAP bmp;
    RECT restored;
    int have_restored;
} App;

static App app;

static int path_in_appdata(wchar_t *out, const wchar_t *file) {
    wchar_t root[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"APPDATA", root, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return 0;
    wchar_t dir[MAX_PATH];
    _snwprintf(dir, MAX_PATH, L"%s\\Klinker", root);
    CreateDirectoryW(dir, NULL);
    _snwprintf(out, MAX_PATH, L"%s\\%s", dir, file);
    return 1;
}

static void load_best(void) {
    FILE *in = _wfopen(app.best_path, L"r");
    if (!in) return;
    int value = 0;
    if (fscanf(in, "%d", &value) == 1 && value > 0) app.best = value;
    fclose(in);
}

static void store_best(void) {
    if (app.game.cheat_score || app.game.score <= app.best) return;
    app.best = app.game.score;
    FILE *out = _wfopen(app.best_path, L"w");
    if (!out) return;
    fprintf(out, "%d\n", app.best);
    fclose(out);
}

static void save_stand(void) {
    if (app.game.phase == PH_OVER) {
        DeleteFileW(app.stand_path);
        app.can_continue = 0;
        store_best();
        return;
    }
    FILE *out = _wfopen(app.stand_path, L"w");
    if (!out) return;
    int ok = game_save(&app.game, out);
    fclose(out);
    if (ok) app.can_continue = 1;
}

static void load_stand(void) {
    FILE *in = _wfopen(app.stand_path, L"r");
    if (!in) return;
    int ok = game_load(&app.game, in);
    fclose(in);
    if (!ok) return;
    app.menu_rank = app.game.rank;
    app.can_continue = 1;
    app.menu = 0;
    app.paused = 0;
    app.shown_level = -1;
}

static void remember_banner(void) {
    if (app.shown_level == app.game.level && app.shown_bonus == app.game.bonus) return;
    app.shown_level = app.game.level;
    app.shown_bonus = app.game.bonus;
    snprintf(app.banner, sizeof app.banner, "Runde %d  ·  %s  ·  %s",
        app.game.level + 1, game_round_name(&app.game), game_rank_title(app.game.rank));
    app.banner_left = 1.8;
}

static void dots(char *dst, int n) {
    char raw[32];
    if (n < 0) n = 0;
    snprintf(raw, sizeof raw, "%d", n);
    int len = (int)strlen(raw);
    int out = 0;
    for (int i = 0; i < len; i++) {
        if (i > 0 && (len - i) % 3 == 0) dst[out++] = '.';
        dst[out++] = raw[i];
    }
    dst[out] = 0;
}

static void draw_text(HDC dc, HFONT font, COLORREF color, int x, int y, int w, int h, const char *utf8, UINT align) {
    wchar_t wide[256];
    if (!utf8 || !MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, 256)) return;
    HFONT old = (HFONT)SelectObject(dc, font);
    SetTextColor(dc, color);
    SetBkMode(dc, TRANSPARENT);
    RECT rect = {x, y, x + w, y + h};
    DrawTextW(dc, wide, -1, &rect, align | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX | DT_END_ELLIPSIS);
    SelectObject(dc, old);
}

static void fill_round(HDC dc, int x, int y, int w, int h, int radius, HBRUSH brush, HPEN pen) {
    HBRUSH old_b = (HBRUSH)SelectObject(dc, brush);
    HPEN old_p = (HPEN)SelectObject(dc, pen);
    RoundRect(dc, x, y, x + w, y + h, radius, radius);
    SelectObject(dc, old_b);
    SelectObject(dc, old_p);
}

static int hit(int x, int y, int rx, int ry, int rw, int rh) {
    return x >= rx && y >= ry && x < rx + rw && y < ry + rh;
}

static void sound_init(void) {
    WAVEFORMATEX fmt;
    memset(&fmt, 0, sizeof fmt);
    fmt.wFormatTag = WAVE_FORMAT_PCM;
    fmt.nChannels = 1;
    fmt.nSamplesPerSec = 44100;
    fmt.wBitsPerSample = 16;
    fmt.nBlockAlign = 2;
    fmt.nAvgBytesPerSec = 44100 * 2;
    if (waveOutOpen(&app.wave, WAVE_MAPPER, &fmt, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR) app.wave = NULL;
}

static void sound_tone(double freq, double dur, double decay, double gain) {
    if (!app.wave || app.muted) return;
    int slot = -1;
    for (int i = 0; i < 6; i++) {
        DWORD flags = app.headers[i].dwFlags;
        if (flags == 0 || (flags & WHDR_DONE)) {
            slot = i;
            break;
        }
    }
    if (slot < 0) return;
    if (app.headers[slot].dwFlags & WHDR_PREPARED) {
        waveOutUnprepareHeader(app.wave, &app.headers[slot], sizeof(WAVEHDR));
    }
    int count = (int)(44100 * dur);
    if (count > 8000) count = 8000;
    if (count < 1) return;
    for (int i = 0; i < count; i++) {
        double t = i / 44100.0;
        double sample = sin(6.283185307179586 * freq * t) * exp(-t * decay) * gain;
        if (sample > 1) sample = 1;
        if (sample < -1) sample = -1;
        app.samples[slot][i] = (int16_t)(sample * 28000);
    }
    memset(&app.headers[slot], 0, sizeof app.headers[slot]);
    app.headers[slot].lpData = (LPSTR)app.samples[slot];
    app.headers[slot].dwBufferLength = (DWORD)(count * 2);
    waveOutPrepareHeader(app.wave, &app.headers[slot], sizeof app.headers[slot]);
    waveOutWrite(app.wave, &app.headers[slot], sizeof app.headers[slot]);
}

static void sound_pitch(int pitch) {
    static const double scale[] = {523.25, 587.33, 659.25, 698.46, 783.99, 880, 987.77};
    if (pitch < 0) pitch = 0;
    if (pitch > 6) pitch = 6;
    sound_tone(scale[pitch], 0.09, 16, 0.28);
}

static void new_round(void) {
    app.game.rank = app.menu_rank;
    game_new(&app.game);
    app.menu = 0;
    app.paused = 0;
    app.admin = 0;
    app.shown_level = -1;
    remember_banner();
    save_stand();
}

static void continue_round(void) {
    load_stand();
    app.menu = 0;
    app.paused = 0;
}

static void press_start(void) {
    if (app.game.phase == PH_OVER) {
        new_round();
        return;
    }
    if (app.paused) {
        app.paused = 0;
        return;
    }
    if (app.game.phase == PH_SERVING || app.game.has_stuck) {
        game_launch(&app.game);
        sound_tone(440, 0.1, 8, 0.22);
        return;
    }
    if (app.game.phase == PH_PLAYING) app.paused = 1;
}

static void toggle_fullscreen(void) {
    if (!app.fullscreen) {
        GetWindowRect(app.hwnd, &app.restored);
        app.have_restored = 1;
        HMONITOR monitor = MonitorFromWindow(app.hwnd, MONITOR_DEFAULTTONEAREST);
        MONITORINFO info;
        info.cbSize = sizeof info;
        GetMonitorInfoW(monitor, &info);
        SetWindowLongPtrW(app.hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
        SetWindowPos(app.hwnd, HWND_TOP, info.rcMonitor.left, info.rcMonitor.top,
            info.rcMonitor.right - info.rcMonitor.left, info.rcMonitor.bottom - info.rcMonitor.top,
            SWP_FRAMECHANGED | SWP_SHOWWINDOW);
        app.fullscreen = 1;
    } else {
        SetWindowLongPtrW(app.hwnd, GWL_STYLE, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VISIBLE);
        if (app.have_restored) {
            SetWindowPos(app.hwnd, NULL, app.restored.left, app.restored.top,
                app.restored.right - app.restored.left, app.restored.bottom - app.restored.top,
                SWP_FRAMECHANGED | SWP_NOZORDER);
        }
        app.fullscreen = 0;
    }
}

static void map_cursor(double *vx, double *vy) {
    POINT point;
    GetCursorPos(&point);
    ScreenToClient(app.hwnd, &point);
    RECT client;
    GetClientRect(app.hwnd, &client);
    int width = client.right > 1 ? client.right : 1;
    int height = client.bottom > 1 ? client.bottom : 1;
    *vx = point.x * (double)VIEW_W / width;
    *vy = point.y * (double)VIEW_H / height;
    app.mouse_x = (int)*vx;
    app.mouse_y = (int)*vy;
}

static void click_admin(int x, int y) {
    int labels_y = 158 + 36;
    const char *ids[] = {
        "million", "lives", "full", "normal", "ball", "slow", "energy", "floor", "skip", "shield",
    };
    for (int i = 0; i < 10; i++) {
        int by = labels_y + i * 36;
        if (!hit(x, y, 54, by, i == 7 ? 180 : 220, 30)) continue;
        if (strcmp(ids[i], "million") == 0) game_cheat_million(&app.game);
        else if (strcmp(ids[i], "lives") == 0) game_cheat_lives(&app.game);
        else if (strcmp(ids[i], "full") == 0) game_cheat_full_paddle(&app.game);
        else if (strcmp(ids[i], "normal") == 0) game_cheat_normal_paddle(&app.game);
        else if (strcmp(ids[i], "ball") == 0) game_cheat_power(&app.game, PW_MULTI);
        else if (strcmp(ids[i], "slow") == 0) game_cheat_power(&app.game, PW_SLOW);
        else if (strcmp(ids[i], "energy") == 0) game_cheat_power(&app.game, PW_THROUGH);
        else if (strcmp(ids[i], "floor") == 0) game_cheat_power(&app.game, PW_FLOOR);
        else if (strcmp(ids[i], "skip") == 0) game_cheat_skip(&app.game);
        else game_cheat_shield(&app.game);
        return;
    }
    if (hit(x, y, 242, labels_y + 7 * 36, 28, 30)) game_cheat_hold_floor(&app.game);
}

static void click_menu(int x, int y) {
    for (int i = 0; i < 4; i++) {
        if (hit(x, y, 330 + i * 140, 340, 128, 44)) app.menu_rank = i;
    }
    if (hit(x, y, 390, 430, 420, 52)) new_round();
    if (app.can_continue && hit(x, y, 390, 496, 420, 48)) continue_round();
}

static void click_game(int x, int y) {
    if (app.admin && hit(x, y, 40, 158, 248, 428)) {
        click_admin(x, y);
        return;
    }
    if (hit(x, y, 1034, 108, 140, 40)) {
        app.menu = 1;
        save_stand();
        return;
    }
    if (hit(x, y, 1034, 156, 140, 40)) {
        app.muted = !app.muted;
        return;
    }
    if (hit(x, y, 1034, 204, 140, 40)) {
        app.mouse_mode = !app.mouse_mode;
        app.key_left = 0;
        app.key_right = 0;
        return;
    }
    if (hit(x, y, 1034, 690, 140, 48)) {
        press_start();
        return;
    }
    int field_top = sy(app.game.field_y + app.game.field_h);
    if (x >= 26 && x < 26 + 980 && y >= field_top && y < field_top + 692) {
        if (app.mouse_mode) app.game.steer = 1, app.game.steer_x = x;
        if (app.paused) {
            app.paused = 0;
            return;
        }
        if (app.game.phase != PH_OVER && (app.game.phase == PH_SERVING || app.game.has_stuck)) {
            game_launch(&app.game);
            sound_tone(440, 0.1, 8, 0.22);
        }
    }
}

static void on_key(WPARAM key, int down, int repeat) {
    if (key == VK_LEFT || key == 'A') app.key_left = down;
    if (key == VK_RIGHT || key == 'D') app.key_right = down;
    if (!down || repeat) return;
    if (key == 'K' && (GetKeyState(VK_MENU) & 0x8000) && (GetKeyState(VK_SHIFT) & 0x8000)) {
        if (!app.menu) app.admin = !app.admin;
        return;
    }
    if (key == VK_ESCAPE) {
        if (app.admin) app.admin = 0;
        else if (app.menu && app.can_continue) app.menu = 0;
        else if (!app.menu) app.paused = !app.paused;
        return;
    }
    if (app.menu) {
        if (key == 'N' || key == VK_RETURN) new_round();
        return;
    }
    if (key == VK_SPACE || key == VK_RETURN) press_start();
    else if (key == 'P') app.paused = !app.paused;
    else if (key == 'M') app.muted = !app.muted;
    else if (key == 'F') toggle_fullscreen();
    else if (key == 'N' && (GetKeyState(VK_CONTROL) & 0x8000)) new_round();
}

static LRESULT CALLBACK proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
        on_key(wp, 1, (lp & (1 << 30)) != 0);
        return 0;
    case WM_KEYUP:
    case WM_SYSKEYUP:
        on_key(wp, 0, 0);
        return 0;
    case WM_LBUTTONDOWN: {
        double x, y;
        map_cursor(&x, &y);
        if (app.menu) click_menu((int)x, (int)y);
        else click_game((int)x, (int)y);
        return 0;
    }
    case WM_DESTROY:
        save_stand();
        PostQuitMessage(0);
        return 0;
    case WM_ERASEBKGND:
        return 1;
    default:
        return DefWindowProcW(hwnd, msg, wp, lp);
    }
}

static void draw_button(HDC dc, int x, int y, int w, int h, const char *label, int hot) {
    HBRUSH brush = CreateSolidBrush(RGB(255, 255, 255));
    /* Weiß liegt nur im Stift. Die Fläche bleibt der blaue Grund, leicht aufgehellt. */
    DeleteObject(brush);
    HBRUSH fill = CreateSolidBrush(hot ? RGB(80, 150, 255) : RGB(45, 132, 250));
    HPEN pen = CreatePen(PS_SOLID, hot ? 2 : 1, RGB(255, 255, 255));
    fill_round(dc, x, y, w, h, 12, fill, pen);
    DeleteObject(fill);
    DeleteObject(pen);
    draw_text(dc, app.font_ui, RGB(255, 255, 255), x, y, w, h, label, DT_CENTER);
}

static unsigned brick_color(const Brick *brick) {
    if (brick->kind == K_STEEL || brick->kind == K_WALL) return STEEL_HEX;
    int style = brick->style;
    if (style < 0 || style > 6) style = 0;
    return BRICK_HEX[style];
}

static void draw_brick(HDC dc, const Brick *brick) {
    if (brick->hp <= 0) return;
    int x = (int)(brick->min_x + 0.5);
    int y = sy(brick->min_y + brick->h);
    int w = (int)(brick->w + 0.5);
    int h = (int)(brick->h + 0.5);
    unsigned color = brick_color(brick);
    if (brick->hp < brick->max_hp) color = 0xE7EEF6;
    HBRUSH fill = CreateSolidBrush(rgb(color));
    HPEN pen = CreatePen(PS_SOLID, 1, RGB(255, 255, 255));
    fill_round(dc, x, y, w, h, 8, fill, pen);
    DeleteObject(fill);
    DeleteObject(pen);
}

static void draw_game(HDC dc) {
    Game *g = &app.game;
    HBRUSH chrome = CreateSolidBrush(rgb(0x1D76F9));
    RECT all = {0, 0, VIEW_W, VIEW_H};
    FillRect(dc, &all, chrome);
    DeleteObject(chrome);

    int field_top = sy(g->field_y + g->field_h);
    HBRUSH field = CreateSolidBrush(rgb(0x0D1753));
    HPEN edge = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
    fill_round(dc, (int)g->field_x, field_top, (int)g->field_w, (int)g->field_h, 16, field, edge);
    DeleteObject(field);
    DeleteObject(edge);

    int dark = g->dark_on && g->phase == PH_PLAYING;
    for (int i = 0; i < g->nbricks; i++) {
        if (dark) {
            int close = 0;
            double cx = g->bricks[i].min_x + g->bricks[i].w * 0.5;
            double cy = g->bricks[i].min_y + g->bricks[i].h * 0.5;
            for (int b = 0; b < g->nballs; b++) {
                double dx = g->balls[b].x - cx;
                double dy = g->balls[b].y - cy;
                if (dx * dx + dy * dy < 160 * 160) close = 1;
            }
            if (!close) continue;
        }
        draw_brick(dc, &g->bricks[i]);
    }

    if (g->floor_up) {
        HBRUSH sill = CreateSolidBrush(rgb(0x7EE0C8));
        RECT bar = {(int)g->field_x + 8, sy(g->field_y + 16), (int)(g->field_x + g->field_w - 8), sy(g->field_y + 8)};
        FillRect(dc, &bar, sill);
        DeleteObject(sill);
    }

    for (int i = 0; i < g->ndrops; i++) {
        int x = (int)g->drops[i].x - 11;
        int y = sy(g->drops[i].y + 11);
        HBRUSH fill = CreateSolidBrush(rgb(game_power_tint(g->drops[i].kind)));
        HPEN pen = CreatePen(PS_SOLID, 1, RGB(255, 255, 255));
        fill_round(dc, x, y, 22, 22, 8, fill, pen);
        DeleteObject(fill);
        DeleteObject(pen);
    }
    for (int i = 0; i < g->nshots; i++) {
        HBRUSH shot = CreateSolidBrush(rgb(0xF2E27A));
        RECT rect = {(int)g->shots[i].x - 2, sy(g->shots[i].y + 12), (int)g->shots[i].x + 2, sy(g->shots[i].y)};
        FillRect(dc, &rect, shot);
        DeleteObject(shot);
    }

    int px = (int)(g->paddle_x - g->paddle_w * 0.5);
    int py = sy(g->paddle_y + g->paddle_h * 0.5);
    int pw = (int)g->paddle_w;
    if (g->ghost_on) {
        HPEN ghost = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
        HBRUSH empty = (HBRUSH)GetStockObject(NULL_BRUSH);
        fill_round(dc, px, py, pw, (int)g->paddle_h, 10, empty, ghost);
        DeleteObject(ghost);
    } else {
        HBRUSH paddle = CreateSolidBrush(rgb(0xF7F1EA));
        HPEN warm = CreatePen(PS_SOLID, 1, rgb(0xF0714A));
        fill_round(dc, px, py, pw, (int)g->paddle_h, 12, paddle, warm);
        DeleteObject(paddle);
        DeleteObject(warm);
    }
    for (int i = 0; i < g->nballs; i++) {
        int bx = (int)(g->balls[i].x - g->ball_r);
        int by = sy(g->balls[i].y + g->ball_r);
        int d = (int)(g->ball_r * 2);
        HBRUSH ball = CreateSolidBrush(rgb(0xFFF4EC));
        HPEN ball_pen = CreatePen(PS_SOLID, 1, rgb(0xF0714A));
        fill_round(dc, bx, by, d, d, d, ball, ball_pen);
        DeleteObject(ball);
        DeleteObject(ball_pen);
    }

    char line[128];
    char number[32];
    draw_text(dc, app.font_big, RGB(255, 255, 255), 28, 16, 220, 42, "KLINKER", DT_LEFT);
    dots(number, g->score);
    snprintf(line, sizeof line, "PUNKTE  %s", number);
    draw_text(dc, app.font_ui, RGB(255, 255, 255), 250, 24, 240, 28, line, DT_LEFT);
    snprintf(line, sizeof line, "LEBEN  %d", g->lives);
    draw_text(dc, app.font_ui, RGB(255, 255, 255), 500, 24, 180, 28, line, DT_LEFT);
    snprintf(line, sizeof line, "RUNDE  %d", g->level + 1);
    draw_text(dc, app.font_ui, RGB(255, 255, 255), 700, 24, 180, 28, line, DT_LEFT);

    if (g->phase == PH_SERVING && !app.paused) {
        draw_text(dc, app.font_ui, RGB(190, 205, 235), 26, sy(g->field_y + 130), 980, 28,
            "Leertaste oder Klick", DT_CENTER);
    }
    if (app.banner_left > 0) {
        draw_text(dc, app.font_big, RGB(255, 255, 255), 26, field_top + 250, 980, 40, app.banner, DT_CENTER);
    }
    if (app.notice_left > 0) {
        draw_text(dc, app.font_ui, app.notice_bad ? rgb(0xE25B4A) : RGB(255, 255, 255),
            26, field_top + 300, 980, 28, app.notice, DT_CENTER);
    }
    if (app.gain_left > 0 && app.gain_value > 0) {
        snprintf(line, sizeof line, "+%d", app.gain_value);
        draw_text(dc, app.font_ui, rgb(0xF0D15A), (int)app.gain_x - 40, sy(app.gain_y + 16), 80, 24, line, DT_CENTER);
    }

    const char *start = "START";
    if (g->phase == PH_OVER) start = "NEU";
    else if (app.paused) start = "WEITER";
    else if (g->phase != PH_SERVING && !g->has_stuck) start = "PAUSE";
    draw_button(dc, 1034, 108, 140, 40, "MENÜ", 0);
    draw_button(dc, 1034, 156, 140, 40, app.muted ? "TON AUS" : "TON AN", 0);
    draw_button(dc, 1034, 204, 140, 40, app.mouse_mode ? "MAUS" : "TASTEN", 0);
    draw_button(dc, 1034, 690, 140, 48, start, 1);
    draw_text(dc, app.font_small, RGB(230, 240, 255), 1034, 430, 140, 18, "REKORD", DT_CENTER);
    dots(number, app.best);
    draw_text(dc, app.font_big, g->score > app.best && g->score > 0 ? rgb(0xF0D15A) : RGB(255, 255, 255),
        1034, 452, 140, 36, number, DT_CENTER);
    draw_text(dc, app.font_small, RGB(220, 232, 255), 1022, 620, 164, 18,
        app.mouse_mode ? "Maus bewegt" : "Pfeile oder A D", DT_CENTER);
    draw_text(dc, app.font_small, RGB(220, 232, 255), 1022, 640, 164, 18, "Leertaste startet", DT_CENTER);

    if (app.paused || g->phase == PH_OVER) {
        HBRUSH dim = CreateSolidBrush(RGB(8, 16, 48));
        RECT veil = {(int)g->field_x + 180, field_top + 230, (int)g->field_x + 800, field_top + 430};
        FillRect(dc, &veil, dim);
        DeleteObject(dim);
        const char *title = "PAUSE";
        const char *detail = "P oder Klick zum Weiterspielen";
        if (g->campaign_done) {
            title = "SATZ GESCHAFFT";
            dots(number, g->score);
            snprintf(line, sizeof line, "208 Runden  ·  %s Punkte", number);
            detail = line;
        } else if (g->phase == PH_OVER) {
            title = "SPIEL VORBEI";
            dots(number, g->score);
            snprintf(line, sizeof line, "%s Punkte", number);
            detail = line;
        }
        draw_text(dc, app.font_big, RGB(255, 255, 255), (int)g->field_x, field_top + 250, (int)g->field_w, 42, title, DT_CENTER);
        draw_text(dc, app.font_ui, RGB(220, 232, 255), (int)g->field_x, field_top + 300, (int)g->field_w, 28, detail, DT_CENTER);
    }

    if (app.admin) {
        HBRUSH plate = CreateSolidBrush(rgb(0x102044));
        HPEN rim = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
        fill_round(dc, 40, 158, 248, 428, 16, plate, rim);
        DeleteObject(plate);
        DeleteObject(rim);
        draw_text(dc, app.font_ui, rgb(0xF0D15A), 40, 166, 248, 24, "ADMIN", DT_CENTER);
        const char *labels[] = {
            "1 Mio Punkte", "99 Leben", "Volle Breite", "Normale Breite", "Extra-Ball",
            "Slow", "Energieball", "Boden", "Nächste Runde",
            app.game.shield ? "Schutz an" : "Schutz aus",
        };
        for (int i = 0; i < 10; i++) draw_button(dc, 54, 194 + i * 36, i == 7 ? 176 : 220, 30, labels[i], 0);
        draw_button(dc, 238, 194 + 7 * 36, 30, 30, app.game.floor_held ? "✓" : "", 0);
    }
}

static void draw_menu(HDC dc) {
    HBRUSH chrome = CreateSolidBrush(rgb(0x1D76F9));
    RECT all = {0, 0, VIEW_W, VIEW_H};
    FillRect(dc, &all, chrome);
    DeleteObject(chrome);
    draw_text(dc, app.font_big, RGB(255, 255, 255), 0, 120, VIEW_W, 64, "KLINKER", DT_CENTER);
    draw_text(dc, app.font_ui, RGB(230, 240, 255), 0, 190, VIEW_W, 28, "Schwierigkeit", DT_CENTER);
    const char *ranks[] = {"Kinder", "Leicht", "Mittel", "Schwer"};
    for (int i = 0; i < 4; i++) draw_button(dc, 330 + i * 140, 340, 128, 44, ranks[i], app.menu_rank == i);
    draw_button(dc, 390, 430, 420, 52, "Neues Spiel", 1);
    if (app.can_continue) draw_button(dc, 390, 496, 420, 48, "Weiter", 0);
    char line[128];
    char number[32];
    dots(number, app.best);
    snprintf(line, sizeof line, "Rekord  %s", number);
    draw_text(dc, app.font_ui, RGB(255, 255, 255), 0, 600, VIEW_W, 28, line, DT_CENTER);
    draw_text(dc, app.font_small, RGB(220, 232, 255), 0, 680, VIEW_W, 22,
        "Leertaste startet   ·   Pfeile oder A und D   ·   Maus", DT_CENTER);
}

static void present(void) {
    if (!app.mem) return;
    HDC dc = app.mem;
    if (app.menu) draw_menu(dc);
    else draw_game(dc);
    HDC window = GetDC(app.hwnd);
    RECT client;
    GetClientRect(app.hwnd, &client);
    SetStretchBltMode(window, HALFTONE);
    StretchBlt(window, 0, 0, client.right, client.bottom, app.mem, 0, 0, VIEW_W, VIEW_H, SRCCOPY);
    ReleaseDC(app.hwnd, window);
}

static void steer(void) {
    app.game.steer = 0;
    if (app.menu || app.paused) return;
    if (app.mouse_mode) {
        double x, y;
        map_cursor(&x, &y);
        int field_top = sy(app.game.field_y + app.game.field_h);
        if (x >= app.game.field_x && x <= app.game.field_x + app.game.field_w && y >= field_top && y <= field_top + app.game.field_h) {
            app.game.steer = 1;
            app.game.steer_x = x;
        }
    } else {
        double speed = 0;
        if (app.key_left) speed -= 1080;
        if (app.key_right) speed += 1080;
        if (speed != 0) {
            app.game.steer = 2;
            app.game.steer_v = speed;
        }
    }
}

static void frame(double dt) {
    if (app.banner_left > 0) app.banner_left -= dt;
    if (app.notice_left > 0) app.notice_left -= dt;
    if (app.gain_left > 0) app.gain_left -= dt;
    if (!app.menu && !app.paused && app.game.phase != PH_OVER) {
        steer();
        int paddle = 0, wall = 0, hurt = 0, cleared = 0, extra = 0, pitch = -1;
        double acc = dt;
        if (acc > 0.05) acc = 0.05;
        const double step = 1.0 / 240.0;
        while (acc >= step) {
            game_clear_flags(&app.game);
            game_step(&app.game, step);
            if (app.game.hit_paddle) paddle = 1;
            if (app.game.hit_wall) wall = 1;
            if (app.game.lost_life) hurt = 1;
            if (app.game.just_cleared) cleared = 1;
            if (app.game.extra_life) extra = 1;
            if (app.game.destroyed_pitch >= 0) pitch = app.game.destroyed_pitch;
            if (app.game.notice[0]) {
                snprintf(app.notice, sizeof app.notice, "%s", app.game.notice);
                app.notice_bad = app.game.notice_bad;
                app.notice_left = 1.4;
            }
            if (app.game.gain > 0) {
                app.gain_value = app.game.gain;
                app.gain_x = app.game.gain_x;
                app.gain_y = app.game.gain_y;
                app.gain_left = 0.35;
            }
            if (app.game.phase == PH_OVER) {
                store_best();
                DeleteFileW(app.stand_path);
                app.can_continue = 0;
            }
            acc -= step;
        }
        if (pitch >= 0) sound_pitch(pitch);
        else if (paddle) sound_tone(196, 0.06, 26, 0.3);
        else if (wall) sound_tone(740, 0.04, 40, 0.16);
        if (hurt) sound_tone(294, 0.2, 8, 0.3);
        if (cleared) sound_tone(784, 0.18, 6, 0.26);
        if (extra) sound_tone(1175, 0.12, 8, 0.24);
        remember_banner();
        app.save_wait += dt;
        if (app.save_wait > 3) {
            app.save_wait = 0;
            save_stand();
        }
    }
    present();
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE prev, LPSTR cmd, int show) {
    (void)prev;
    (void)cmd;
    (void)show;
    HMODULE user = GetModuleHandleW(L"user32.dll");
    BOOL (WINAPI *aware)(HANDLE) = (BOOL (WINAPI *)(HANDLE))GetProcAddress(user, "SetProcessDpiAwarenessContext");
    if (aware) aware((HANDLE)-4);

    path_in_appdata(app.stand_path, L"stand.txt");
    path_in_appdata(app.best_path, L"rekord.txt");
    game_init(&app.game);
    app.mouse_mode = 1;
    app.menu = 1;
    app.menu_rank = RANK_MEDIUM;
    app.game.rank = RANK_MEDIUM;
    app.shown_level = -1;
    app.shown_bonus = -2;
    load_best();
    app.can_continue = GetFileAttributesW(app.stand_path) != INVALID_FILE_ATTRIBUTES;
    sound_init();
    app.font_big = CreateFontW(-34, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    app.font_ui = CreateFontW(-18, 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    app.font_small = CreateFontW(-14, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");

    WNDCLASSW klass;
    memset(&klass, 0, sizeof klass);
    klass.lpfnWndProc = proc;
    klass.hInstance = instance;
    klass.lpszClassName = L"KlinkerFenster";
    klass.hCursor = LoadCursor(NULL, IDC_ARROW);
    klass.hbrBackground = CreateSolidBrush(rgb(0x1D76F9));
    RegisterClassW(&klass);

    RECT work;
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    int client_w = VIEW_W;
    int client_h = VIEW_H;
    int avail_w = work.right - work.left - 40;
    int avail_h = work.bottom - work.top - 40;
    if (client_w > avail_w || client_h > avail_h) {
        double sx = avail_w / (double)VIEW_W;
        double syy = avail_h / (double)VIEW_H;
        double scale = sx < syy ? sx : syy;
        client_w = (int)(VIEW_W * scale);
        client_h = (int)(VIEW_H * scale);
    }
    RECT bounds = {0, 0, client_w, client_h};
    DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    AdjustWindowRect(&bounds, style, FALSE);
    int width = bounds.right - bounds.left;
    int height = bounds.bottom - bounds.top;
    int x = work.left + ((work.right - work.left) - width) / 2;
    int y = work.top + ((work.bottom - work.top) - height) / 2;
    app.hwnd = CreateWindowExW(0, L"KlinkerFenster", L"Klinker", style, x, y, width, height, NULL, NULL, instance, NULL);
    ShowWindow(app.hwnd, SW_SHOW);
    UpdateWindow(app.hwnd);

    HDC window = GetDC(app.hwnd);
    app.mem = CreateCompatibleDC(window);
    app.bmp = CreateCompatibleBitmap(window, VIEW_W, VIEW_H);
    SelectObject(app.mem, app.bmp);
    ReleaseDC(app.hwnd, window);

    LARGE_INTEGER freq, last;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&last);
    for (;;) {
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) goto done;
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        double dt = (double)(now.QuadPart - last.QuadPart) / (double)freq.QuadPart;
        last = now;
        if (dt < 0) dt = 0;
        if (dt > 0.1) dt = 0.1;
        frame(dt);
        Sleep(1);
    }
done:
    if (app.wave) waveOutClose(app.wave);
    return 0;
}

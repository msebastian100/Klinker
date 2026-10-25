#include "game.h"
#include "levels.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void spawn_defender(Game *g);

static const double BASE_SPEED = 300;
static const double PADDLE_STEP = 36;
static const double PADDLE_MIN = 64;
static const double PADDLE_MAX = 214;
static const int RANK_LIVES[] = {7, 5, 3, 2};
static const int RANK_MAX_LIVES[] = {12, 9, 7, 5};
static const double RANK_PADDLE[] = {168, 140, 118, 86};
static const double RANK_PACE[] = {0.78, 0.9, 1, 1.12};
static const double RANK_CAP[] = {390, 440, 480, 540};
static const double RANK_CREEP[] = {1.5, 2.5, 4, 6};
static const double RANK_CEILING[] = {430, 500, 580, 640};
static const double RANK_TIME[] = {2, 1.35, 1, 0.7};
static const double RANK_SCORE[] = {0.6, 0.85, 1, 1.3};
static const char *RANK_TITLE[] = {"Kinder", "Leicht", "Mittel", "Schwer"};
static const char *BONUS_TITLE[] = {"Barriere", "Ausbruch", "Hüpfer", "Enten", "Jagd", "Wellen"};
static const char *POWER_TITLE[] = {
    "Breiter Schläger", "Schmaler Schläger", "Extra-Ball", "Langsamer", "Schneller",
    "Extra-Leben", "Klebriger Schläger", "Energieball", "1000 Punkte", "Boden",
    "Explosiv", "Eingefroren", "Chaos", "Schwacher Ball", "Dunkelheit", "Waffe",
    "Goldregen", "Joker", "Magnet", "Gegenmagnet", "Geisterschläger", "Reset",
    "Sieben Sekunden", "Zufall",
};
static const unsigned POWER_TINT[] = {
    0x3DDC97, 0xE25B4A, 0x7EC8F0, 0x6AA4F0, 0xF0A04A, 0xF07AB0, 0xF0D15A, 0xF4F7FF,
    0xE6C15A, 0x7EE0C8, 0xF07A4A, 0xD7F1FF, 0xC06ADF, 0x8E96A8, 0x3A4380, 0xF2E27A,
    0xE6C15A, 0xC06ADF, 0x7EC8F0, 0xE25B4A, 0xB7C0D4, 0xF4F7FF, 0x7EE0C8, 0xF07AB0,
};
static const int POWER_BAD[] = {
    0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0,
};
static const int MALUS[] = {
    PW_NARROW, PW_FAST, PW_FREEZE, PW_CHAOS, PW_WEAK, PW_DARK, PW_REPEL, PW_GHOST,
};

static uint32_t rng_state = 1;

static void rng_seed(void) {
    rng_state = (uint32_t)time(NULL) ^ 0xA3C59AC3u;
    if (rng_state == 0) rng_state = 1;
}

static uint32_t rng_u(void) {
    uint32_t x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_state = x ? x : 1;
    return rng_state;
}

static int rng_int(int lo, int hi) {
    if (hi <= lo) return lo;
    return lo + (int)(rng_u() % (uint32_t)(hi - lo + 1));
}

static double rng_unit(void) {
    return (rng_u() >> 8) / 16777216.0;
}

static double rng_range(double lo, double hi) {
    return lo + (hi - lo) * rng_unit();
}

static void shuffle_int(int *a, int n) {
    for (int i = n - 1; i > 0; i--) {
        int j = rng_int(0, i);
        int tmp = a[i];
        a[i] = a[j];
        a[j] = tmp;
    }
}

static double dmin(double a, double b) { return a < b ? a : b; }
static double dmax(double a, double b) { return a > b ? a : b; }
static int imin(int a, int b) { return a < b ? a : b; }

static double brick_right(const Brick *b) { return b->min_x + b->w; }
static double brick_top(const Brick *b) { return b->min_y + b->h; }

static void set_notice(Game *g, const char *text, int bad) {
    snprintf(g->notice, sizeof g->notice, "%s", text);
    g->notice_bad = bad;
}

const char *game_round_name(const Game *g) {
    if (g->bonus >= 0 && g->bonus < 6) return BONUS_TITLE[g->bonus];
    int index = g->level;
    if (index < 0) index = 0;
    if (index >= k_level_count) index = k_level_count - 1;
    return k_levels[index].name;
}

const char *game_rank_title(int rank) {
    if (rank < 0 || rank > RANK_HARD) rank = RANK_MEDIUM;
    return RANK_TITLE[rank];
}

const char *game_power_title(int power) {
    if (power < 0 || power >= PW_COUNT) return "";
    return POWER_TITLE[power];
}

unsigned game_power_tint(int power) {
    if (power < 0 || power >= PW_COUNT) return 0xF4F7FF;
    return POWER_TINT[power];
}

static double field_mid(const Game *g) { return g->field_x + g->field_w * 0.5; }
static double field_top(const Game *g) { return g->field_y + g->field_h; }
static double travel(const Game *g) { return g->speed * g->tempo; }

static double growth(int steps) {
    double v = 1;
    for (int i = 0; i < steps; i++) v *= 1.04;
    return v;
}

static double pace_of(const Game *g, int level) {
    if (level < 0) level = 0;
    double grown = BASE_SPEED * growth(level) * RANK_PACE[g->rank];
    double cap = dmin(RANK_CEILING[g->rank], RANK_CAP[g->rank] + (level > 8 ? level - 8 : 0) * RANK_CREEP[g->rank]);
    double v = dmax(grown, 80);
    return dmin(v, cap);
}

static double span_of(const Game *g, double seconds) {
    double v = seconds * RANK_TIME[g->rank];
    return v < 0.4 ? 0.4 : v;
}

static void cool(double *timer, double dt) {
    if (*timer > 0) *timer = dmax(0, *timer - dt);
}

static void rescale_balls(Game *g) {
    double mag = travel(g);
    for (int i = 0; i < g->nballs; i++) {
        if (g->balls[i].stuck) continue;
        double now = hypot(g->balls[i].vx, g->balls[i].vy);
        if (now < 1) continue;
        double k = mag / now;
        g->balls[i].vx *= k;
        g->balls[i].vy *= k;
    }
}

static void keep_angle(Game *g, int index) {
    Ball *b = &g->balls[index];
    double mag = hypot(b->vx, b->vy);
    if (mag < 1) return;
    double min_y = mag * 0.28;
    if (fabs(b->vy) >= min_y) return;
    b->vy = (b->vy >= 0 ? 1 : -1) * min_y;
    double now = hypot(b->vx, b->vy);
    b->vx *= mag / now;
    b->vy *= mag / now;
}

static void clamp_paddle(Game *g) {
    double half = g->paddle_w * 0.5;
    double lo = g->field_x + half + 4;
    double hi = g->field_x + g->field_w - half - 4;
    if (lo >= hi) {
        g->paddle_x = field_mid(g);
        return;
    }
    if (g->paddle_x < lo) g->paddle_x = lo;
    if (g->paddle_x > hi) g->paddle_x = hi;
}

static void move_paddle(Game *g, double dt) {
    if (g->phase == PH_PLAYING && g->freeze_time > 0) return;
    if (g->steer == 1) g->paddle_x = g->steer_x;
    else if (g->steer == 2) g->paddle_x += g->steer_v * dt;
    clamp_paddle(g);
}

static void stick_ball(Game *g, int bob) {
    if (g->nballs <= 0) {
        g->nballs = 1;
        memset(&g->balls[0], 0, sizeof g->balls[0]);
        g->balls[0].alive = 1;
        g->balls[0].skip = -1;
    }
    double bob_y = bob ? sin(g->time * 4.2) * 1.25 : 0;
    g->balls[0].x = g->paddle_x;
    g->balls[0].y = g->paddle_y + g->paddle_h * 0.5 + g->ball_r + 2.5 + bob_y;
    g->balls[0].vx = 0;
    g->balls[0].vy = 0;
    g->balls[0].stuck = 1;
    g->balls[0].grip = 0;
    g->balls[0].alive = 1;
}

static void clear_timers(Game *g) {
    g->tempo = 1;
    g->tempo_time = 0;
    g->sticky_time = 0;
    g->through_time = 0;
    g->floor_time = g->floor_held ? 10000 : 0;
    g->blast_time = 0;
    g->freeze_time = 0;
    g->chaos_time = 0;
    g->weak_time = 0;
    g->dark_time = 0;
    g->weapon_time = 0;
    g->gold_time = 0;
    g->attract_time = 0;
    g->repel_time = 0;
    g->ghost_time = 0;
    g->weapon_cool = 0;
}

static void begin_serve(Game *g) {
    g->phase = PH_SERVING;
    g->combo = 0;
    clear_timers(g);
    g->nshots = 0;
    g->ndrops = 0;
    g->nballs = 1;
    memset(&g->balls[0], 0, sizeof g->balls[0]);
    g->balls[0].alive = 1;
    g->balls[0].skip = -1;
    g->balls[0].stuck = 1;
    stick_ball(g, 0);
}

static int near_brick(const Brick *a, const Brick *b) {
    const double reach = 14;
    return a->min_x < brick_right(b) + reach && b->min_x < brick_right(a) + reach
        && a->min_y < brick_top(b) + reach && b->min_y < brick_top(a) + reach;
}

static void award_life(Game *g) {
    int bucket = g->score / 10000;
    if (bucket > g->life_bucket && g->lives < 7) {
        g->lives += 1;
        g->extra_life = 1;
    }
    if (bucket > g->life_bucket) g->life_bucket = bucket;
}

static void lose_life(Game *g);

static void add_ball(Game *g) {
    if (g->nballs >= 6 || g->nballs <= 0) return;
    Ball copy = g->balls[0];
    copy.skip = -1;
    copy.stuck = 0;
    copy.alive = 1;
    double turn = g->balls[0].stuck ? 0.45 : 0.7;
    double vx = g->balls[0].stuck ? 0 : g->balls[0].vx;
    double vy = g->balls[0].stuck ? travel(g) : g->balls[0].vy;
    copy.vx = vx * cos(turn) - vy * sin(turn);
    copy.vy = fabs(vx * sin(turn) + vy * cos(turn));
    if (fabs(copy.vy) < 40) copy.vy = travel(g);
    g->balls[g->nballs++] = copy;
    rescale_balls(g);
}

static void apply_power(Game *g, int kind);

static void damage(Game *g, int index, int from_blast) {
    if (index < 0 || index >= g->nbricks) return;
    Brick *brick = &g->bricks[index];
    if (brick->hp <= 0 || brick->kind == K_WALL || brick->kind == K_SEED) return;
    if (brick->kind == K_ENERGY && g->through_time <= 0 && !from_blast) {
        set_notice(g, "Nur der Energieball", 0);
        return;
    }
    if (!from_blast && g->weak_time > 0 && g->through_time <= 0 && rng_unit() < 0.4) return;
    brick->hp -= 1;
    if (brick->hp > 0) {
        g->cracked = 1;
        if (brick->kind == K_HEAL) brick->mend = 4;
        return;
    }
    int gift = brick->power;
    Brick origin = *brick;
    brick->hp = 0;
    brick->power = -1;
    if (origin.counts) g->remaining -= 1;
    g->combo = imin(g->combo + 1, 99);
    int shower = g->gold_time > 0 ? 2 : 1;
    int add = (int)(origin.points * imin(g->combo, 8) * shower * RANK_SCORE[g->rank] + 0.5);
    g->score += add;
    g->gain += add;
    g->gain_x = origin.min_x + origin.w * 0.5;
    g->gain_y = origin.min_y + origin.h * 0.5;
    if (origin.pitch > g->destroyed_pitch) g->destroyed_pitch = origin.pitch;
    if (gift >= 0 && g->ndrops < 8) {
        Drop *d = &g->drops[g->ndrops++];
        d->kind = gift;
        d->x = g->gain_x;
        d->y = g->gain_y;
        d->alive = 1;
    }
    award_life(g);
    if (origin.kind == K_TNT) {
        for (int other = 0; other < g->nbricks; other++) {
            if (other == index || g->bricks[other].hp <= 0) continue;
            if (!near_brick(&origin, &g->bricks[other])) continue;
            if (g->phase != PH_PLAYING) break;
            damage(g, other, 1);
        }
    }
    if (origin.kind == K_GROW) {
        for (int other = 0; other < g->nbricks; other++) {
            Brick *seed = &g->bricks[other];
            if (seed->kind != K_SEED || seed->hp > 0) continue;
            if (!near_brick(&origin, seed)) continue;
            seed->kind = K_PLAIN;
            seed->counts = 1;
            seed->hp = 1;
            seed->max_hp = 1;
            seed->points = 4;
            seed->style = 1;
            g->remaining += 1;
        }
    }
    if (g->remaining <= 0 && g->phase == PH_PLAYING) {
        if (g->bonus == B_DEFENDER && g->bonus_wave < 2) {
            g->bonus_wave += 1;
            spawn_defender(g);
            return;
        }
        g->phase = PH_CLEARED;
        g->clear_timer = 1.05;
        g->just_cleared = 1;
        g->combo = 0;
        g->ndrops = 0;
        g->nshots = 0;
        return;
    }
    if (!(g->blast_time > 0) || from_blast || g->phase != PH_PLAYING) return;
    for (int other = 0; other < g->nbricks; other++) {
        if (other == index || g->bricks[other].hp <= 0) continue;
        if (!near_brick(&origin, &g->bricks[other])) continue;
        while (g->bricks[other].hp > 0 && g->phase == PH_PLAYING) damage(g, other, 1);
    }
}

static int spec_of(char ch, int *style, int *points, int *pitch, int *hp, int *kind, int *counts) {
    *kind = K_PLAIN;
    *counts = 1;
    switch (ch) {
    case '1': *style = 0; *points = 7; *pitch = 6; *hp = 1; return 1;
    case '2': *style = 1; *points = 5; *pitch = 5; *hp = 1; return 1;
    case '3': *style = 2; *points = 4; *pitch = 4; *hp = 1; return 1;
    case '4': *style = 3; *points = 3; *pitch = 3; *hp = 1; return 1;
    case '5': *style = 4; *points = 3; *pitch = 2; *hp = 1; return 1;
    case '6': *style = 5; *points = 2; *pitch = 1; *hp = 1; return 1;
    case '7': *style = 6; *points = 1; *pitch = 0; *hp = 1; return 1;
    case '#': *style = 7; *points = 8; *pitch = 3; *hp = 2; *kind = K_STEEL; return 1;
    case '=': *style = 7; *points = 0; *pitch = 0; *hp = 1; *kind = K_WALL; *counts = 0; return 1;
    case '&': *style = 0; *points = 12; *pitch = 6; *hp = 1; *kind = K_ENERGY; return 1;
    case '@': *style = 6; *points = 9; *pitch = 4; *hp = 1; *kind = K_CHAOS; return 1;
    case '8': *style = 2; *points = 10; *pitch = 3; *hp = 3; *kind = K_TOUGH; return 1;
    case '%': *style = 3; *points = 8; *pitch = 2; *hp = 2; *kind = K_HEAL; return 1;
    case '*': *style = 0; *points = 6; *pitch = 5; *hp = 1; *kind = K_TNT; return 1;
    case '+': *style = 3; *points = 6; *pitch = 2; *hp = 1; *kind = K_GROW; return 1;
    default: return 0;
    }
}

static void stamp(Game *g, const char *const *rows, int nrows, int sink) {
    int cols = 1;
    int sprouts = 0;
    for (int r = 0; r < nrows; r++) {
        int n = (int)strlen(rows[r]);
        if (n > cols) cols = n;
        if (strchr(rows[r], '+')) sprouts = 1;
    }
    const double gap = 9;
    const double side = 18;
    const double brick_h = 22;
    double top = 20 + (sink > 0 ? sink : 0) * (brick_h + gap);
    double avail = g->field_w - side * 2 - gap * (cols > 1 ? cols - 1 : 0);
    double brick_w = avail / (cols > 0 ? cols : 1);
    g->nbricks = 0;
    for (int r = 0; r < nrows; r++) {
        int n = (int)strlen(rows[r]);
        for (int c = 0; c < n; c++) {
            char ch = rows[r][c];
            int style, points, pitch, hp, kind, counts;
            if (ch == '.' && sprouts) {
                style = 1; points = 4; pitch = 2; hp = 0; kind = K_SEED; counts = 0;
            } else if (!spec_of(ch, &style, &points, &pitch, &hp, &kind, &counts)) {
                continue;
            }
            if (g->nbricks >= MAX_BRICKS) return;
            Brick *b = &g->bricks[g->nbricks++];
            memset(b, 0, sizeof *b);
            b->min_x = g->field_x + side + c * (brick_w + gap);
            b->min_y = field_top(g) - top - brick_h - r * (brick_h + gap);
            b->w = brick_w;
            b->h = brick_h;
            b->hp = hp;
            b->max_hp = hp > 1 ? hp : 1;
            b->points = points;
            b->style = style;
            b->pitch = pitch;
            b->power = -1;
            b->kind = kind;
            b->counts = counts;
        }
    }
    g->remaining = 0;
    for (int i = 0; i < g->nbricks; i++) {
        if (g->bricks[i].counts && g->bricks[i].hp > 0) g->remaining += 1;
    }
}

static void spawn_defender(Game *g) {
    const char *row = "2222222222222";
    stamp(g, &row, 1, 2);
}

static void plant_energy(Game *g) {
    int has = 0;
    for (int i = 0; i < g->nbricks; i++) if (g->bricks[i].kind == K_ENERGY) has = 1;
    if (!has) return;
    for (int i = 0; i < g->nbricks; i++) {
        if (g->bricks[i].kind == K_PLAIN && g->bricks[i].hp > 0) {
            g->bricks[i].power = PW_THROUGH;
            return;
        }
    }
}

static void sprinkle(Game *g) {
    int cand[MAX_BRICKS];
    int nc = 0;
    for (int i = 0; i < g->nbricks; i++) {
        if (g->bricks[i].kind == K_PLAIN && g->bricks[i].max_hp == 1) cand[nc++] = i;
    }
    if (nc < 4) {
        plant_energy(g);
        return;
    }
    shuffle_int(cand, nc);
    int kinds[PW_COUNT];
    for (int i = 0; i < PW_COUNT; i++) kinds[i] = i;
    shuffle_int(kinds, PW_COUNT);
    int kind_count = rng_int(4, 6);
    int has_bad = 0;
    for (int i = 0; i < kind_count; i++) if (POWER_BAD[kinds[i]]) has_bad = 1;
    if (g->rank != RANK_KIDS && !has_bad) kinds[0] = MALUS[rng_int(0, 7)];
    if (g->rank == RANK_KIDS) {
        int w = 0;
        for (int i = 0; i < kind_count; i++) if (!POWER_BAD[kinds[i]]) kinds[w++] = kinds[i];
        kind_count = w;
        if (kind_count == 0) {
            kinds[0] = PW_WIDE;
            kinds[1] = PW_SLOW;
            kinds[2] = PW_MULTI;
            kinds[3] = PW_LIFE;
            kind_count = 4;
        }
    } else if (g->rank == RANK_EASY) {
        int kept = 0;
        int w = 0;
        for (int i = 0; i < kind_count; i++) {
            if (!POWER_BAD[kinds[i]]) kinds[w++] = kinds[i];
            else if (!kept) {
                kinds[w++] = kinds[i];
                kept = 1;
            }
        }
        kind_count = w;
    } else if (g->rank == RANK_HARD) {
        int bad = 0;
        for (int i = 0; i < kind_count; i++) if (POWER_BAD[kinds[i]]) bad += 1;
        int slot = 0;
        while (bad < 2 && slot < kind_count) {
            if (!POWER_BAD[kinds[slot]]) {
                kinds[slot] = MALUS[rng_int(0, 7)];
                bad += 1;
            }
            slot += 1;
        }
    }
    int count = imin(nc, rng_int(5, 8));
    for (int i = 0; i < count; i++) g->bricks[cand[i]].power = kinds[i % kind_count];
    plant_energy(g);
}

static const LevelDef *layout_for(int level) {
    int index = level;
    if (index < 0) index = 0;
    if (index >= k_level_count) index = k_level_count - 1;
    return &k_levels[index];
}

static void build_level(Game *g) {
    const LevelDef *def = layout_for(g->level);
    stamp(g, def->rows, def->nrows, def->sink);
    sprinkle(g);
}

static void lay_bonus(Game *g, int pick) {
    const char *barrier[] = {
        "1111111111111", "2222222222222", "3333333333333", "4444444444444",
    };
    const char *outbreak[] = {"......1......", ".....222.....", "......1......"};
    const char *jack[] = {"......8......"};
    const char *ducks[] = {"1.1.1.1.1.1.1", ".2.2.2.2.2.2.", "3.3.3.3.3.3.3"};
    const char *hunter[] = {"1.2.3.4.5.6.1"};
    switch (pick) {
    case B_BARRIER: stamp(g, barrier, 4, 1); break;
    case B_OUTBREAK: stamp(g, outbreak, 3, 2); break;
    case B_JACK:
        stamp(g, jack, 1, 2);
        for (int i = 0; i < g->nbricks; i++) {
            if (g->bricks[i].hp > 0) {
                g->bricks[i].hp = 4;
                g->bricks[i].max_hp = 4;
                g->bricks[i].kind = K_TOUGH;
                break;
            }
        }
        break;
    case B_DUCKS: stamp(g, ducks, 3, 1); break;
    case B_HUNTER:
        stamp(g, hunter, 1, 2);
        for (int i = 0; i < g->nbricks; i++) g->bricks[i].drift = (i % 2 == 0) ? 1 : -1;
        break;
    case B_DEFENDER: spawn_defender(g); break;
    default: break;
    }
}

static void start_bonus(Game *g) {
    int pick = (g->level / 4) % 6;
    g->bonus = pick;
    g->bonus_clock = 0;
    g->bonus_wave = 0;
    g->bonus_left = (pick == B_JACK) ? 22 : (pick == B_DUCKS || pick == B_HUNTER) ? 16 : 0;
    lay_bonus(g, pick);
    sprinkle(g);
    begin_serve(g);
    set_notice(g, BONUS_TITLE[pick], 0);
}

static void finish_campaign(Game *g) {
    g->bonus = -1;
    g->campaign_done = 1;
    g->just_finished = 1;
    g->phase = PH_OVER;
    set_notice(g, "Satz geschafft", 0);
    g->nballs = 0;
    g->ndrops = 0;
    g->nshots = 0;
}

static void advance(Game *g) {
    if (g->level + 1 >= k_level_count) {
        finish_campaign(g);
        return;
    }
    if (g->bonus >= 0) {
        g->bonus = -1;
        g->bonus_clock = 0;
        g->bonus_left = 0;
    } else if (!g->bonus_played && (g->level + 1) % 4 == 0) {
        g->bonus_played = 1;
        start_bonus(g);
        return;
    }
    g->bonus_played = 0;
    g->level += 1;
    g->speed = pace_of(g, g->level);
    build_level(g);
    clamp_paddle(g);
    begin_serve(g);
}

static void lower_barrier(Game *g) {
    if (g->bonus != B_BARRIER || g->nbricks <= 0) return;
    double drop = g->bricks[0].h + 9;
    for (int i = 0; i < g->nbricks; i++) g->bricks[i].min_y -= drop;
}

static void breach(Game *g) {
    double line = g->paddle_y + g->paddle_h + 10;
    int hit = 0;
    for (int i = 0; i < g->nbricks; i++) {
        if (g->bricks[i].hp > 0 && g->bricks[i].counts && g->bricks[i].min_y < line) hit = 1;
    }
    if (!hit) return;
    double lift = ((g->nbricks > 0 ? g->bricks[0].h : 22) + 9) * 2;
    for (int i = 0; i < g->nbricks; i++) g->bricks[i].min_y += lift;
    lose_life(g);
}

static void sprout(Game *g) {
    int hosts[MAX_BRICKS];
    int nh = 0;
    for (int i = 0; i < g->nbricks; i++) if (g->bricks[i].hp > 0) hosts[nh++] = i;
    if (nh <= 0 || g->nbricks >= MAX_BRICKS) return;
    Brick host = g->bricks[hosts[rng_int(0, nh - 1)]];
    double opts[4][2] = {
        {host.w + 9, 0}, {-(host.w + 9), 0}, {0, host.h + 9}, {0, -(host.h + 9)},
    };
    int order[4] = {0, 1, 2, 3};
    shuffle_int(order, 4);
    for (int n = 0; n < 4; n++) {
        double x = host.min_x + opts[order[n]][0];
        double y = host.min_y + opts[order[n]][1];
        if (x < g->field_x + 12 || x + host.w > g->field_x + g->field_w - 12) continue;
        if (y < g->paddle_y + 90 || y > field_top(g) - 36) continue;
        int occupied = 0;
        for (int i = 0; i < g->nbricks; i++) {
            if (g->bricks[i].hp > 0 && fabs(g->bricks[i].min_x - x) < 8 && fabs(g->bricks[i].min_y - y) < 8)
                occupied = 1;
        }
        if (occupied) continue;
        Brick *b = &g->bricks[g->nbricks++];
        memset(b, 0, sizeof *b);
        b->min_x = x;
        b->min_y = y;
        b->w = host.w;
        b->h = host.h;
        b->hp = 1;
        b->max_hp = 1;
        b->points = 4;
        b->style = g->bonus_wave % 7;
        b->pitch = 3;
        b->power = -1;
        b->kind = K_PLAIN;
        b->counts = 1;
        g->remaining += 1;
        g->bonus_wave += 1;
        return;
    }
}

static void jump_jack(Game *g) {
    int index = -1;
    for (int i = 0; i < g->nbricks; i++) if (g->bricks[i].hp > 0) { index = i; break; }
    if (index < 0) return;
    const int cols = 7, rows = 4;
    const double gap = 9;
    double span = g->bricks[index].w + gap;
    double left = field_mid(g) - span * cols * 0.5;
    int col = rng_int(0, cols - 1);
    int row = rng_int(0, rows - 1);
    g->bricks[index].min_x = left + col * span;
    g->bricks[index].min_y = field_top(g) - 70 - row * (g->bricks[index].h + gap);
}

static int bonus_timed(int bonus) {
    return bonus == B_JACK || bonus == B_DUCKS || bonus == B_HUNTER;
}

static void tick_bonus(Game *g, double dt) {
    if (g->bonus < 0) return;
    g->bonus_clock += dt;
    if (bonus_timed(g->bonus)) {
        g->bonus_left -= dt;
        if (g->bonus_left <= 0) {
            g->phase = PH_CLEARED;
            g->clear_timer = 0.7;
            g->just_cleared = 1;
            g->ndrops = 0;
            g->nshots = 0;
            return;
        }
    }
    if (g->bonus == B_BARRIER) {
        breach(g);
    } else if (g->bonus == B_OUTBREAK) {
        if (g->bonus_clock >= 2.2 && g->bonus_wave < 8) {
            g->bonus_clock = 0;
            sprout(g);
        }
    } else if (g->bonus == B_JACK) {
        if (g->bonus_clock >= 1.15) {
            g->bonus_clock = 0;
            jump_jack(g);
        }
    } else if (g->bonus == B_HUNTER) {
        double step = 90 * dt;
        for (int i = 0; i < g->nbricks; i++) {
            Brick *b = &g->bricks[i];
            if (b->hp <= 0 || b->drift == 0) continue;
            b->min_x += b->drift * step;
            if (b->min_x < g->field_x + 16) {
                b->min_x = g->field_x + 16;
                b->drift = 1;
            } else if (brick_right(b) > g->field_x + g->field_w - 16) {
                b->min_x = g->field_x + g->field_w - 16 - b->w;
                b->drift = -1;
            }
        }
    } else if (g->bonus == B_DEFENDER) {
        for (int i = 0; i < g->nbricks; i++) if (g->bricks[i].hp > 0) g->bricks[i].min_y -= 26 * dt;
        breach(g);
    }
}

static void tick_weapon(Game *g, double dt) {
    if (g->weapon_time <= 0) {
        g->nshots = 0;
        return;
    }
    g->weapon_cool -= dt;
    if (g->weapon_cool <= 0 && g->nshots < 6) {
        g->weapon_cool = 0.42;
        g->shots[g->nshots].x = g->paddle_x;
        g->shots[g->nshots].y = g->paddle_y + g->paddle_h;
        g->shots[g->nshots].alive = 1;
        g->nshots += 1;
    }
    int hits[MAX_SHOTS];
    int nh = 0;
    for (int i = 0; i < g->nshots; i++) {
        g->shots[i].y += 560 * dt;
        if (g->shots[i].y > field_top(g)) {
            g->shots[i].alive = 0;
            continue;
        }
        for (int b = 0; b < g->nbricks; b++) {
            Brick *brick = &g->bricks[b];
            if (brick->hp <= 0) continue;
            if (g->shots[i].x >= brick->min_x && g->shots[i].x <= brick_right(brick)
                && g->shots[i].y >= brick->min_y && g->shots[i].y <= brick_top(brick)) {
                g->shots[i].alive = 0;
                hits[nh++] = b;
                break;
            }
        }
    }
    int w = 0;
    for (int i = 0; i < g->nshots; i++) if (g->shots[i].alive) g->shots[w++] = g->shots[i];
    g->nshots = w;
    for (int i = 0; i < nh && g->phase == PH_PLAYING; i++) damage(g, hits[i], 0);
}

static void release_stuck(Game *g) {
    double mag = travel(g);
    for (int i = 0; i < g->nballs; i++) {
        if (!g->balls[i].stuck) continue;
        double hit = g->balls[i].grip / dmax(1, g->paddle_w * 0.5);
        if (hit > 1) hit = 1;
        if (hit < -1) hit = -1;
        double angle = hit * 0.9;
        g->balls[i].vx = sin(angle) * mag;
        g->balls[i].vy = fabs(cos(angle)) * mag;
        if (fabs(g->balls[i].vy) < 40) g->balls[i].vy = mag;
        g->balls[i].stuck = 0;
    }
}

static int fell_off(Game *g, int index) {
    Ball *b = &g->balls[index];
    double left = g->field_x + g->ball_r;
    double right = g->field_x + g->field_w - g->ball_r;
    double top = field_top(g) - g->ball_r;
    if (b->x < left) {
        b->x = left;
        b->vx = fabs(b->vx);
        g->hit_wall = 1;
        keep_angle(g, index);
    } else if (b->x > right) {
        b->x = right;
        b->vx = -fabs(b->vx);
        g->hit_wall = 1;
        keep_angle(g, index);
    }
    if (b->y > top) {
        b->y = top;
        b->vy = -fabs(b->vy);
        g->hit_wall = 1;
        keep_angle(g, index);
    }
    double sill = g->field_y + 11 + g->ball_r;
    if (g->floor_time > 0 && b->vy < 0 && b->y <= sill) {
        b->y = sill;
        b->vy = fabs(b->vy);
        g->hit_wall = 1;
        keep_angle(g, index);
    }
    return b->y < g->field_y - g->ball_r;
}

static void collide_paddle(Game *g, int index) {
    Ball *ball = &g->balls[index];
    double half_w = g->paddle_w * 0.5;
    double half_h = g->paddle_h * 0.5;
    double left = g->paddle_x - half_w;
    double right = g->paddle_x + half_w;
    double bottom = g->paddle_y - half_h;
    double top = g->paddle_y + half_h;
    int coming_down = ball->vy < 0;
    int over_x = ball->x >= left - g->ball_r * 0.25 && ball->x <= right + g->ball_r * 0.25;
    int on_top = ball->y >= g->paddle_y && ball->y - g->ball_r <= top + 6;
    if (coming_down && over_x && on_top) {
        if (g->sticky_time > 0) {
            ball->stuck = 1;
            double grip = ball->x - g->paddle_x;
            double limit = half_w * 0.86;
            if (grip > limit) grip = limit;
            if (grip < -limit) grip = -limit;
            ball->grip = grip;
            ball->vx = 0;
            ball->vy = 0;
            g->hit_paddle = 1;
            lower_barrier(g);
            return;
        }
        double hit = (ball->x - g->paddle_x) / half_w;
        if (hit > 1) hit = 1;
        if (hit < -1) hit = -1;
        double angle = hit * 1.02;
        double mag = travel(g);
        ball->vx = sin(angle) * mag;
        ball->vy = fabs(cos(angle)) * mag;
        ball->y = top + g->ball_r + 0.8;
        g->hit_paddle = 1;
        g->combo = 0;
        lower_barrier(g);
        return;
    }
    int beside = ball->y <= top && ball->y >= bottom - g->ball_r;
    if (beside && ball->x < left && ball->x + g->ball_r >= left) {
        ball->x = left - g->ball_r - 0.6;
        ball->vx = -fabs(ball->vx);
        g->hit_paddle = 1;
    } else if (beside && ball->x > right && ball->x - g->ball_r <= right) {
        ball->x = right + g->ball_r + 0.6;
        ball->vx = fabs(ball->vx);
        g->hit_paddle = 1;
    }
}

static void collide_bricks(Game *g, int index) {
    Ball *ball = &g->balls[index];
    double r = g->ball_r;
    int best = -1;
    double best_pen = 1e300;
    double nx = 0, ny = 0, push_x = 0, push_y = 0;
    for (int i = 0; i < g->nbricks; i++) {
        Brick *brick = &g->bricks[i];
        if (brick->hp <= 0) continue;
        double cx = ball->x;
        if (cx < brick->min_x) cx = brick->min_x;
        if (cx > brick_right(brick)) cx = brick_right(brick);
        double cy = ball->y;
        if (cy < brick->min_y) cy = brick->min_y;
        if (cy > brick_top(brick)) cy = brick_top(brick);
        double dx = ball->x - cx;
        double dy = ball->y - cy;
        double d2 = dx * dx + dy * dy;
        if (d2 > r * r) continue;
        double nnx, nny, pen, px, py;
        if (d2 > 0.000001) {
            double d = sqrt(d2);
            nnx = dx / d;
            nny = dy / d;
            pen = r - d;
            px = nnx * pen;
            py = nny * pen;
        } else {
            double left = ball->x - brick->min_x;
            double right = brick_right(brick) - ball->x;
            double down = ball->y - brick->min_y;
            double up = brick_top(brick) - ball->y;
            double m = left;
            int side = 0;
            if (right < m) { m = right; side = 1; }
            if (down < m) { m = down; side = 2; }
            if (up < m) { side = 3; }
            if (side == 0) { nnx = -1; nny = 0; pen = left + r; px = -(left + r); py = 0; }
            else if (side == 1) { nnx = 1; nny = 0; pen = right + r; px = right + r; py = 0; }
            else if (side == 2) { nnx = 0; nny = -1; pen = down + r; px = 0; py = -(down + r); }
            else { nnx = 0; nny = 1; pen = up + r; px = 0; py = up + r; }
        }
        if (pen < best_pen) {
            best_pen = pen;
            best = i;
            nx = nnx;
            ny = nny;
            push_x = px;
            push_y = py;
        }
    }
    if (best < 0) return;
    ball->x += push_x;
    ball->y += push_y;
    if (g->chaos_time > 0 || g->bricks[best].kind == K_CHAOS) {
        double mag = dmax(travel(g), hypot(ball->vx, ball->vy));
        double aim = atan2(ny, nx) + rng_range(-0.85, 0.85);
        ball->vx = cos(aim) * mag;
        ball->vy = sin(aim) * mag;
    } else {
        double dot = ball->vx * nx + ball->vy * ny;
        if (dot < 0) {
            ball->vx -= 2 * dot * nx;
            ball->vy -= 2 * dot * ny;
        }
    }
    keep_angle(g, index);
    damage(g, best, 0);
}

static void pierce_bricks(Game *g, int index) {
    Ball *ball = &g->balls[index];
    double r = g->ball_r;
    int hit = -1;
    for (int i = 0; i < g->nbricks; i++) {
        Brick *brick = &g->bricks[i];
        if (brick->hp <= 0) continue;
        double cx = ball->x;
        if (cx < brick->min_x) cx = brick->min_x;
        if (cx > brick_right(brick)) cx = brick_right(brick);
        double cy = ball->y;
        if (cy < brick->min_y) cy = brick->min_y;
        if (cy > brick_top(brick)) cy = brick_top(brick);
        double dx = ball->x - cx;
        double dy = ball->y - cy;
        if (dx * dx + dy * dy <= r * r) {
            hit = i;
            break;
        }
    }
    if (hit < 0) {
        ball->skip = -1;
        return;
    }
    if (g->bricks[hit].kind == K_WALL) {
        ball->skip = -1;
        collide_bricks(g, index);
        return;
    }
    if (ball->skip == hit) return;
    ball->skip = hit;
    damage(g, hit, 0);
}

static int caught(const Game *g, const Drop *drop) {
    double half = g->paddle_w * 0.5;
    int near_x = fabs(drop->x - g->paddle_x) < half + 26;
    int near_y = drop->y <= g->paddle_y + g->paddle_h && drop->y >= g->paddle_y - 30;
    return near_x && near_y;
}

static void apply_power(Game *g, int kind) {
    if (kind < 0 || kind >= PW_COUNT) return;
    set_notice(g, POWER_TITLE[kind], POWER_BAD[kind]);
    switch (kind) {
    case PW_WIDE:
        if (g->wide_held || g->paddle_w > PADDLE_MAX) g->paddle_w = dmin(g->field_w, g->paddle_w + PADDLE_STEP);
        else g->paddle_w = dmin(PADDLE_MAX, g->paddle_w + PADDLE_STEP);
        break;
    case PW_NARROW:
        if (g->wide_held || g->paddle_w > PADDLE_MAX) {
            g->wide_held = 0;
            g->paddle_w = RANK_PADDLE[g->rank];
        } else {
            g->paddle_w = dmax(PADDLE_MIN, g->paddle_w - PADDLE_STEP);
        }
        break;
    case PW_MULTI: add_ball(g); break;
    case PW_SLOW: {
        int already = g->tempo < 0.99 && g->tempo_time > 0;
        g->tempo = (BASE_SPEED * RANK_PACE[g->rank]) / dmax(g->speed, 1);
        g->tempo_time = already ? g->tempo_time + span_of(g, 20) : span_of(g, 20);
        rescale_balls(g);
        break;
    }
    case PW_FAST: {
        int already = g->tempo > 1.01 && g->tempo_time > 0;
        g->tempo = RANK_CEILING[g->rank] / dmax(g->speed, 1);
        g->tempo_time = already ? g->tempo_time + span_of(g, 20) : span_of(g, 20);
        rescale_balls(g);
        break;
    }
    case PW_LIFE:
        if (g->lives < RANK_MAX_LIVES[g->rank]) {
            g->lives += 1;
            g->extra_life = 1;
        }
        break;
    case PW_STICKY: g->sticky_time += span_of(g, 20); break;
    case PW_THROUGH: g->through_time += span_of(g, 5); break;
    case PW_BONUS: {
        int jackpot = (int)(1000 * RANK_SCORE[g->rank] + 0.5);
        g->score += jackpot;
        g->gain += jackpot;
        g->gain_x = g->paddle_x;
        g->gain_y = g->paddle_y + 36;
        break;
    }
    case PW_FLOOR:
        g->floor_time = g->floor_held ? 10000 : g->floor_time + span_of(g, 10);
        break;
    case PW_BLAST: g->blast_time += span_of(g, 10); break;
    case PW_FREEZE: g->freeze_time = span_of(g, 1); break;
    case PW_CHAOS: g->chaos_time += span_of(g, 10); break;
    case PW_WEAK: g->weak_time += span_of(g, 10); break;
    case PW_DARK: g->dark_time += span_of(g, 20); break;
    case PW_WEAPON: g->weapon_time += span_of(g, 15); break;
    case PW_GOLD: g->gold_time += span_of(g, 15); break;
    case PW_JOKER: {
        g->ndrops = 0;
        int good[PW_COUNT];
        int ng = 0;
        for (int i = 0; i < PW_COUNT; i++) {
            if (!POWER_BAD[i] && i != PW_JOKER && i != PW_MYSTERY && i != PW_RESET) good[ng++] = i;
        }
        if (ng > 0) {
            int pick = good[rng_int(0, ng - 1)];
            apply_power(g, pick);
            char line[96];
            snprintf(line, sizeof line, "Joker: %s", POWER_TITLE[pick]);
            set_notice(g, line, 0);
        }
        break;
    }
    case PW_ATTRACT:
        g->repel_time = 0;
        g->attract_time += span_of(g, 18);
        break;
    case PW_REPEL:
        g->attract_time = 0;
        g->repel_time += span_of(g, 12);
        break;
    case PW_GHOST: g->ghost_time += span_of(g, 12); break;
    case PW_RESET:
        if (g->tempo > 1) {
            g->tempo = 1;
            g->tempo_time = 0;
            rescale_balls(g);
        }
        g->freeze_time = 0;
        g->chaos_time = 0;
        g->weak_time = 0;
        g->dark_time = 0;
        g->repel_time = 0;
        g->ghost_time = 0;
        if (!g->wide_held && g->paddle_w < RANK_PADDLE[g->rank]) g->paddle_w = RANK_PADDLE[g->rank];
        break;
    case PW_CLOCK: {
        double extra = span_of(g, 7);
        if (g->sticky_time > 0) g->sticky_time += extra;
        if (g->through_time > 0) g->through_time += extra;
        if (!g->floor_held && g->floor_time > 0) g->floor_time += extra;
        if (g->blast_time > 0) g->blast_time += extra;
        if (g->chaos_time > 0) g->chaos_time += extra;
        if (g->weak_time > 0) g->weak_time += extra;
        if (g->dark_time > 0) g->dark_time += extra;
        if (g->weapon_time > 0) g->weapon_time += extra;
        if (g->gold_time > 0) g->gold_time += extra;
        if (g->attract_time > 0) g->attract_time += extra;
        if (g->repel_time > 0) g->repel_time += extra;
        if (g->ghost_time > 0) g->ghost_time += extra;
        if (g->tempo_time > 0) g->tempo_time += extra;
        break;
    }
    case PW_MYSTERY: {
        int pool[PW_COUNT];
        int np = 0;
        for (int i = 0; i < PW_COUNT; i++) if (i != PW_MYSTERY && i != PW_JOKER) pool[np++] = i;
        if (np > 0) apply_power(g, pool[rng_int(0, np - 1)]);
        break;
    }
    default: break;
    }
    clamp_paddle(g);
}

static void move_drops(Game *g, double dt) {
    int caught_kinds[MAX_DROPS];
    int nc = 0;
    for (int i = 0; i < g->ndrops; i++) {
        g->drops[i].y -= 150 * dt;
        if (caught(g, &g->drops[i])) {
            caught_kinds[nc++] = g->drops[i].kind;
            g->drops[i].alive = 0;
        } else if (g->drops[i].y < g->field_y - 24) {
            g->drops[i].alive = 0;
        }
    }
    int w = 0;
    for (int i = 0; i < g->ndrops; i++) if (g->drops[i].alive) g->drops[w++] = g->drops[i];
    g->ndrops = w;
    for (int i = 0; i < nc; i++) {
        if (g->phase == PH_PLAYING || g->phase == PH_SERVING) apply_power(g, caught_kinds[i]);
    }
}

static void mend_bricks(Game *g, double dt) {
    for (int i = 0; i < g->nbricks; i++) {
        Brick *b = &g->bricks[i];
        if (b->kind != K_HEAL || b->hp <= 0 || b->hp >= b->max_hp) continue;
        if (b->mend <= 0) b->mend = 4;
        b->mend -= dt;
        if (b->mend > 0) continue;
        b->hp += 1;
        b->mend = b->hp < b->max_hp ? 4 : 0;
    }
}

static void lose_life(Game *g) {
    if (g->shield) {
        begin_serve(g);
        set_notice(g, "Schutz", 0);
        return;
    }
    g->lives -= 1;
    g->combo = 0;
    g->lost_life = 1;
    g->phase = PH_DYING;
    g->die_timer = 0.6;
    g->nballs = 0;
    g->ndrops = 0;
    g->nshots = 0;
}

static void refresh_derived(Game *g) {
    g->floor_up = g->floor_time > 0;
    g->dark_on = g->dark_time > 0;
    g->ghost_on = g->ghost_time > 0;
    g->has_stuck = 0;
    if (g->phase == PH_PLAYING) {
        for (int i = 0; i < g->nballs; i++) if (g->balls[i].stuck) g->has_stuck = 1;
    }
}

static void play(Game *g, double dt) {
    move_paddle(g, dt);
    cool(&g->sticky_time, dt);
    cool(&g->through_time, dt);
    if (g->floor_held) g->floor_time = 10000;
    else cool(&g->floor_time, dt);
    cool(&g->blast_time, dt);
    cool(&g->freeze_time, dt);
    cool(&g->chaos_time, dt);
    cool(&g->weak_time, dt);
    cool(&g->dark_time, dt);
    cool(&g->weapon_time, dt);
    cool(&g->gold_time, dt);
    cool(&g->attract_time, dt);
    cool(&g->repel_time, dt);
    cool(&g->ghost_time, dt);
    tick_bonus(g, dt);
    if (g->phase != PH_PLAYING) return;
    tick_weapon(g, dt);
    if (g->tempo_time > 0) {
        g->tempo_time -= dt;
        if (g->tempo_time <= 0) {
            g->tempo = 1;
            rescale_balls(g);
        }
    }
    mend_bricks(g, dt);
    int piercing = g->through_time > 0;
    for (int i = 0; i < g->nballs; i++) {
        Ball *b = &g->balls[i];
        if (!b->alive) continue;
        if (b->stuck) {
            b->x = g->paddle_x + b->grip;
            b->y = g->paddle_y + g->paddle_h * 0.5 + g->ball_r + 2;
            b->vx = 0;
            b->vy = 0;
            continue;
        }
        if (b->vy < 0) {
            if (g->attract_time > 0) b->vx += (g->paddle_x - b->x) * dt * 1.6;
            else if (g->repel_time > 0) {
                double away = b->x - g->paddle_x;
                b->vx += (away == 0 ? 80 : away) * dt * 0.9;
            }
        }
        b->x += b->vx * dt;
        b->y += b->vy * dt;
        if (fell_off(g, i)) {
            b->alive = 0;
            continue;
        }
        collide_paddle(g, i);
        if (g->phase != PH_PLAYING) return;
        if (piercing) pierce_bricks(g, i);
        else collide_bricks(g, i);
        if (g->phase != PH_PLAYING) return;
    }
    int w = 0;
    for (int i = 0; i < g->nballs; i++) if (g->balls[i].alive) g->balls[w++] = g->balls[i];
    g->nballs = w;
    if (g->nballs == 0) {
        lose_life(g);
        return;
    }
    move_drops(g, dt);
}

void game_clear_flags(Game *g) {
    g->hit_paddle = 0;
    g->hit_wall = 0;
    g->lost_life = 0;
    g->just_cleared = 0;
    g->just_finished = 0;
    g->extra_life = 0;
    g->cracked = 0;
    g->destroyed_pitch = -1;
    g->gain = 0;
    g->notice[0] = 0;
    g->notice_bad = 0;
}

void game_init(Game *g) {
    memset(g, 0, sizeof *g);
    rng_seed();
    g->field_x = 26;
    g->field_y = 22;
    g->field_w = 980;
    g->field_h = 692;
    g->paddle_h = 14;
    g->ball_r = 6.5;
    g->rank = RANK_MEDIUM;
    g->bonus = -1;
    g->paddle_y = g->field_y + 46;
    g->paddle_x = field_mid(g);
    g->paddle_w = RANK_PADDLE[g->rank];
}

void game_new(Game *g) {
    int rank = g->rank;
    if (rank < 0 || rank > RANK_HARD) rank = RANK_MEDIUM;
    double fx = g->field_x, fy = g->field_y, fw = g->field_w, fh = g->field_h;
    double ph = g->paddle_h, br = g->ball_r;
    int steer = g->steer;
    double sx = g->steer_x, sv = g->steer_v;
    memset(g, 0, sizeof *g);
    g->field_x = fx;
    g->field_y = fy;
    g->field_w = fw;
    g->field_h = fh;
    g->paddle_h = ph;
    g->ball_r = br;
    g->rank = rank;
    g->steer = steer;
    g->steer_x = sx;
    g->steer_v = sv;
    g->bonus = -1;
    g->lives = RANK_LIVES[rank];
    g->speed = pace_of(g, 0);
    g->paddle_w = RANK_PADDLE[rank];
    g->paddle_y = fy + 46;
    g->paddle_x = field_mid(g);
    build_level(g);
    begin_serve(g);
}

void game_launch(Game *g) {
    if (g->phase == PH_PLAYING) {
        release_stuck(g);
        return;
    }
    if (g->phase != PH_SERVING) return;
    stick_ball(g, 0);
    double angle = rng_range(-0.42, 0.42);
    double mag = travel(g);
    if (g->nballs <= 0) {
        g->nballs = 1;
        memset(&g->balls[0], 0, sizeof g->balls[0]);
    }
    g->balls[0].stuck = 0;
    g->balls[0].alive = 1;
    g->balls[0].vx = sin(angle) * mag;
    g->balls[0].vy = cos(angle) * mag;
    g->phase = PH_PLAYING;
}

void game_step(Game *g, double dt) {
    g->time += dt;
    switch (g->phase) {
    case PH_PLAYING: play(g, dt); break;
    case PH_SERVING:
        move_paddle(g, dt);
        stick_ball(g, 1);
        break;
    case PH_DYING:
        g->die_timer -= dt;
        if (g->die_timer <= 0) {
            if (g->lives <= 0) g->phase = PH_OVER;
            else begin_serve(g);
        }
        break;
    case PH_CLEARED:
        move_paddle(g, dt);
        stick_ball(g, 0);
        g->clear_timer -= dt;
        if (g->clear_timer <= 0) advance(g);
        break;
    default: break;
    }
    refresh_derived(g);
}

static int cheat_live(const Game *g) {
    return g->phase == PH_SERVING || g->phase == PH_PLAYING;
}

void game_cheat_power(Game *g, int power) {
    if (!cheat_live(g)) return;
    apply_power(g, power);
}

void game_cheat_skip(Game *g) {
    if (!cheat_live(g)) return;
    advance(g);
}

void game_cheat_million(Game *g) {
    g->cheat_score = 1;
    g->score = g->score >= 1000000 ? g->score + 1000000 : 1000000;
}

void game_cheat_lives(Game *g) {
    g->lives = g->lives >= 99 ? g->lives + 100 : 99;
}

void game_cheat_full_paddle(Game *g) {
    g->wide_held = 1;
    g->paddle_w = g->field_w;
    clamp_paddle(g);
}

void game_cheat_normal_paddle(Game *g) {
    g->wide_held = 0;
    g->paddle_w = RANK_PADDLE[g->rank];
    clamp_paddle(g);
}

int game_cheat_shield(Game *g) {
    g->shield = !g->shield;
    return g->shield;
}

int game_cheat_hold_floor(Game *g) {
    g->floor_held = !g->floor_held;
    g->floor_time = g->floor_held ? 10000 : 0;
    return g->floor_held;
}

int game_save(const Game *g, FILE *out) {
    if (!out) return 0;
    if (fprintf(out, "klinker 1\n") < 0) return 0;
    if (fprintf(out, "%d %d %d %d %.17g %.17g %.17g %d\n",
            g->rank, g->level, g->score, g->lives, g->speed, g->paddle_w, g->paddle_x, g->phase) < 0)
        return 0;
    if (fprintf(out, "%d %d %d %.17g %d %d\n",
            g->bonus, g->bonus_played, g->bonus_wave, g->bonus_left, g->combo, g->life_bucket) < 0)
        return 0;
    if (fprintf(out, "%.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g\n",
            g->tempo, g->tempo_time, g->sticky_time, g->through_time, g->floor_time, g->blast_time,
            g->freeze_time, g->chaos_time, g->weak_time, g->dark_time, g->weapon_time, g->gold_time,
            g->attract_time) < 0)
        return 0;
    if (fprintf(out, "%.17g %.17g %d %d %d %d\n",
            g->repel_time, g->ghost_time, g->shield, g->floor_held, g->wide_held, g->cheat_score) < 0)
        return 0;
    if (fprintf(out, "%d\n", g->nbricks) < 0) return 0;
    for (int i = 0; i < g->nbricks; i++) {
        const Brick *b = &g->bricks[i];
        if (fprintf(out, "%d %d %d %d %d %d %d %d %.17g %.17g %.17g %.17g %.17g %.17g\n",
                b->hp, b->max_hp, b->points, b->style, b->pitch, b->power, b->kind, b->counts,
                b->min_x, b->min_y, b->w, b->h, b->mend, b->drift) < 0)
            return 0;
    }
    if (fprintf(out, "%d\n", g->nballs) < 0) return 0;
    for (int i = 0; i < g->nballs; i++) {
        const Ball *b = &g->balls[i];
        if (fprintf(out, "%.17g %.17g %.17g %.17g %.17g %d %d %d\n",
                b->x, b->y, b->vx, b->vy, b->grip, b->stuck, b->skip, b->alive) < 0)
            return 0;
    }
    return 1;
}

int game_load(Game *g, FILE *in) {
    if (!in) return 0;
    char tag[32];
    int version = 0;
    if (fscanf(in, "%31s %d", tag, &version) != 2 || strcmp(tag, "klinker") != 0 || version != 1) return 0;
    Game next = *g;
    if (fscanf(in, "%d %d %d %d %lf %lf %lf %d",
            &next.rank, &next.level, &next.score, &next.lives, &next.speed, &next.paddle_w, &next.paddle_x, &next.phase) != 8)
        return 0;
    if (next.rank < 0 || next.rank > RANK_HARD) return 0;
    if (next.level < 0 || next.level >= k_level_count) return 0;
    if (fscanf(in, "%d %d %d %lf %d %d",
            &next.bonus, &next.bonus_played, &next.bonus_wave, &next.bonus_left, &next.combo, &next.life_bucket) != 6)
        return 0;
    if (fscanf(in, "%lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf",
            &next.tempo, &next.tempo_time, &next.sticky_time, &next.through_time, &next.floor_time,
            &next.blast_time, &next.freeze_time, &next.chaos_time, &next.weak_time, &next.dark_time,
            &next.weapon_time, &next.gold_time, &next.attract_time) != 13)
        return 0;
    if (fscanf(in, "%lf %lf %d %d %d %d",
            &next.repel_time, &next.ghost_time, &next.shield, &next.floor_held, &next.wide_held, &next.cheat_score) != 6)
        return 0;
    if (fscanf(in, "%d", &next.nbricks) != 1 || next.nbricks < 0 || next.nbricks > MAX_BRICKS) return 0;
    for (int i = 0; i < next.nbricks; i++) {
        Brick *b = &next.bricks[i];
        memset(b, 0, sizeof *b);
        if (fscanf(in, "%d %d %d %d %d %d %d %d %lf %lf %lf %lf %lf %lf",
                &b->hp, &b->max_hp, &b->points, &b->style, &b->pitch, &b->power, &b->kind, &b->counts,
                &b->min_x, &b->min_y, &b->w, &b->h, &b->mend, &b->drift) != 14)
            return 0;
    }
    if (fscanf(in, "%d", &next.nballs) != 1 || next.nballs < 0 || next.nballs > MAX_BALLS) return 0;
    for (int i = 0; i < next.nballs; i++) {
        Ball *b = &next.balls[i];
        memset(b, 0, sizeof *b);
        if (fscanf(in, "%lf %lf %lf %lf %lf %d %d %d",
                &b->x, &b->y, &b->vx, &b->vy, &b->grip, &b->stuck, &b->skip, &b->alive) != 8)
            return 0;
    }
    next.remaining = 0;
    for (int i = 0; i < next.nbricks; i++) {
        if (next.bricks[i].counts && next.bricks[i].hp > 0) next.remaining += 1;
    }
    next.ndrops = 0;
    next.nshots = 0;
    if (next.phase == PH_DYING || next.phase == PH_OVER) next.phase = PH_SERVING;
    *g = next;
    refresh_derived(g);
    return 1;
}

static int fail_test(const char *message) {
    fprintf(stderr, "self-test: %s\n", message);
    return 1;
}

int game_self_test(void) {
    if (k_level_count != 208) return fail_test("nicht 208 Runden");
    if (strcmp(k_levels[0].name, "Klassiker") != 0) return fail_test("erste Runde");
    for (int i = 0; i < k_level_count; i++) {
        for (int j = i + 1; j < k_level_count; j++) {
            if (strcmp(k_levels[i].name, k_levels[j].name) == 0) return fail_test("doppelter Name");
        }
    }
    Game g;
    game_init(&g);
    g.rank = RANK_MEDIUM;
    game_new(&g);
    if (g.lives != 3 || fabs(g.paddle_w - 118) > 0.1) return fail_test("Mittel");
    if (g.remaining != 78) return fail_test("Klassiker");
    g.rank = RANK_KIDS;
    game_new(&g);
    if (g.lives != 7 || fabs(g.paddle_w - 168) > 0.1) return fail_test("Kinder");
    for (int i = 0; i < g.nbricks; i++) {
        if (g.bricks[i].power >= 0 && POWER_BAD[g.bricks[i].power]) return fail_test("Kinder-Malus");
    }
    game_launch(&g);
    if (g.phase != PH_PLAYING || g.balls[0].vy <= 0) return fail_test("Abschlag");

    game_init(&g);
    game_new(&g);
    g.level = 3;
    g.bonus_played = 0;
    g.phase = PH_CLEARED;
    g.clear_timer = 0;
    game_step(&g, 0.02);
    if (g.bonus != B_BARRIER || g.phase != PH_SERVING) return fail_test("Bonus");
    double y0 = g.bricks[0].min_y;
    g.phase = PH_PLAYING;
    g.nballs = 1;
    memset(&g.balls[0], 0, sizeof g.balls[0]);
    g.balls[0].alive = 1;
    g.balls[0].skip = -1;
    g.balls[0].x = g.field_x + 40;
    g.balls[0].y = g.field_y + 220;
    g.balls[0].vy = 80;
    for (int i = 0; i < 240 * 4; i++) game_step(&g, 1.0 / 240.0);
    if (fabs(g.bricks[0].min_y - y0) > 0.01) return fail_test("Barriere lief von allein");
    g.balls[0].alive = 1;
    g.nballs = 1;
    g.phase = PH_PLAYING;
    g.balls[0].x = g.paddle_x;
    g.balls[0].y = g.paddle_y + 18;
    g.balls[0].vx = 0;
    g.balls[0].vy = -400;
    game_step(&g, 1.0 / 60.0);
    if (g.bricks[0].min_y > y0 - 10) return fail_test("Barriere bleibt oben");

    game_init(&g);
    game_new(&g);
    g.phase = PH_PLAYING;
    g.nballs = 1;
    g.balls[0].alive = 1;
    g.balls[0].stuck = 0;
    g.ndrops = 1;
    g.drops[0].kind = PW_JOKER;
    g.drops[0].alive = 1;
    g.drops[0].x = g.paddle_x;
    g.drops[0].y = g.paddle_y;
    game_step(&g, 1.0 / 60.0);
    if (strncmp(g.notice, "Joker", 5) != 0 && g.notice[0] == 0) return fail_test("Joker");

    game_init(&g);
    game_new(&g);
    g.level = k_level_count - 1;
    g.bonus = -1;
    g.phase = PH_CLEARED;
    g.clear_timer = 0;
    game_step(&g, 0.02);
    if (!g.campaign_done || g.phase != PH_OVER) return fail_test("Satzende");
    printf("self-test ok runden=%d\n", k_level_count);
    return 0;
}

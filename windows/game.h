#pragma once

#include <stdio.h>

enum { VIEW_W = 1200, VIEW_H = 800 };
enum { MAX_BRICKS = 512, MAX_BALLS = 8, MAX_DROPS = 12, MAX_SHOTS = 8 };

enum {
    PH_SERVING, PH_PLAYING, PH_DYING, PH_CLEARED, PH_OVER
};

enum {
    RANK_KIDS, RANK_EASY, RANK_MEDIUM, RANK_HARD
};

enum {
    PW_WIDE, PW_NARROW, PW_MULTI, PW_SLOW, PW_FAST, PW_LIFE, PW_STICKY, PW_THROUGH,
    PW_BONUS, PW_FLOOR, PW_BLAST, PW_FREEZE, PW_CHAOS, PW_WEAK, PW_DARK, PW_WEAPON,
    PW_GOLD, PW_JOKER, PW_ATTRACT, PW_REPEL, PW_GHOST, PW_RESET, PW_CLOCK, PW_MYSTERY,
    PW_COUNT
};

enum {
    K_PLAIN, K_STEEL, K_WALL, K_ENERGY, K_CHAOS, K_TOUGH, K_HEAL, K_TNT, K_GROW, K_SEED
};

enum {
    B_BARRIER, B_OUTBREAK, B_JACK, B_DUCKS, B_HUNTER, B_DEFENDER
};

typedef struct {
    double x, y, vx, vy, grip;
    int stuck, skip, alive;
} Ball;

typedef struct {
    double min_x, min_y, w, h, mend, drift;
    int hp, max_hp, points, style, pitch, power, kind, counts;
} Brick;

typedef struct {
    int kind, alive;
    double x, y;
} Drop;

typedef struct {
    double x, y;
    int alive;
} Shot;

typedef struct {
    double field_x, field_y, field_w, field_h;
    double paddle_x, paddle_y, paddle_w, paddle_h, ball_r;
    double speed, time;
    int phase, rank, level, score, lives, combo, remaining;
    int nbricks, nballs, ndrops, nshots;
    Brick bricks[MAX_BRICKS];
    Ball balls[MAX_BALLS];
    Drop drops[MAX_DROPS];
    Shot shots[MAX_SHOTS];
    int bonus; /* -1 aus */
    int bonus_played, bonus_wave, life_bucket;
    double tempo, tempo_time, sticky_time, through_time, floor_time, blast_time;
    double freeze_time, chaos_time, weak_time, dark_time, weapon_time, gold_time;
    double attract_time, repel_time, ghost_time, weapon_cool;
    double bonus_left, bonus_clock, die_timer, clear_timer;
    int campaign_done;
    int shield, floor_held, wide_held, cheat_score;
    int hit_paddle, hit_wall, lost_life, just_cleared, extra_life, cracked;
    int destroyed_pitch, gain, just_finished;
    double gain_x, gain_y;
    int notice_bad;
    char notice[96];
    int floor_up, dark_on, ghost_on, has_stuck;
    int steer; /* 0 still, 1 absolute, 2 geschwindigkeit */
    double steer_x, steer_v;
} Game;

void game_init(Game *g);
void game_new(Game *g);
void game_clear_flags(Game *g);
void game_step(Game *g, double dt);
void game_launch(Game *g);
const char *game_round_name(const Game *g);
const char *game_rank_title(int rank);
const char *game_power_title(int power);
unsigned game_power_tint(int power);

void game_cheat_power(Game *g, int power);
void game_cheat_skip(Game *g);
void game_cheat_million(Game *g);
void game_cheat_lives(Game *g);
void game_cheat_full_paddle(Game *g);
void game_cheat_normal_paddle(Game *g);
int game_cheat_shield(Game *g);
int game_cheat_hold_floor(Game *g);

int game_save(const Game *g, FILE *out);
int game_load(Game *g, FILE *in);
int game_self_test(void);

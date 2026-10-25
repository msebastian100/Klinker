#pragma once

typedef struct {
    const char *name;
    int sink;
    const char *const *rows;
    int nrows;
} LevelDef;

extern const LevelDef k_levels[];
extern const int k_level_count;

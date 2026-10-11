#ifndef MAJA_CORE_H
#define MAJA_CORE_H

char *maja_list_json(const char *path);
char *maja_search_json(const char *path, const char *query);
char *maja_run_operation(const char *command, const char *argument1, const char *argument2);
void maja_string_free(char *value);

#endif

/* Exercise the iOS backing-file path and Xbox RAM aliasing on the Mac. */
#include "platform/win32_compat.h"
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c); return 1; } } while (0)
int main(void) {
    char directory[] = "/tmp/takedawn-ios-map-XXXXXX";
    char *original = getenv("TMPDIR") ? strdup(getenv("TMPDIR")) : NULL;
    CHECK(mkdtemp(directory));
    CHECK(setenv("TMPDIR",directory,1)==0);
    const size_t length = 64 * 1024 * 1024;
    HANDLE memory = CreateFileMappingA(INVALID_HANDLE_VALUE,NULL,PAGE_READWRITE,0,(DWORD)length,NULL);
    CHECK(memory);
    unsigned char *a = MapViewOfFileEx(memory,FILE_MAP_ALL_ACCESS,0,0,length,NULL);
    unsigned char *b = MapViewOfFileEx(memory,FILE_MAP_ALL_ACCESS,0,0,length,NULL);
    CHECK(a && b && a!=b);
    a[0]=0x12; a[length-1]=0x34;
    CHECK(b[0]==0x12 && b[length-1]==0x34);
    b[length/2]=0x56;
    CHECK(a[length/2]==0x56);
    CHECK(UnmapViewOfFile(a));
    CHECK(b[0]==0x12 && b[length-1]==0x34 && b[length/2]==0x56);
    CHECK(UnmapViewOfFile(b));
    CHECK(CloseHandle(memory));
    DIR *dir=opendir(directory);
    CHECK(dir);
    struct dirent *entry;
    int remaining=0;
    while ((entry=readdir(dir))) if (strcmp(entry->d_name,".") && strcmp(entry->d_name,"..")) remaining++;
    closedir(dir);
    CHECK(remaining==0);
    CHECK(rmdir(directory)==0);
    if (original) { setenv("TMPDIR",original,1); free(original); } else unsetenv("TMPDIR");
    puts("iOS memory backing: 64 MiB shared aliases and unlinked-file cleanup passed");
    return 0;
}

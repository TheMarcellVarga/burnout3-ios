#include "recomp_types.h"
#include "platform/recomp_env.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
RECOMP_TLS uint32_t g_eax,g_ebx,g_ecx,g_edx,g_esi,g_edi,g_esp;
ptrdiff_t g_xbox_mem_offset;
static void (*hooks[4])(void);
static int requested;
void recomp_patch_on_mark(const char *name,void (*fn)(void)) {
    const char *names[]={"si_items","si_select","pe_items","pe_select"};
    for(int i=0;i<4;i++) if(!strcmp(name,names[i])) hooks[i]=fn;
}
void sub_001D2879(void) { g_eax=0x700000; g_ecx=123; g_edx=456; g_esp+=12; }
void bo3_ios_request_settings(void) { requested++; }
extern void bo3_menu_entry_start(void);
#define U16(a) (*(uint16_t *)((uintptr_t)g_xbox_mem_offset+(a)))
#define U32(a) (*(uint32_t *)((uintptr_t)g_xbox_mem_offset+(a)))
#define U8(a) (*(uint8_t *)((uintptr_t)g_xbox_mem_offset+(a)))
#define CHECK(x) do { if(!(x)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x); return 1; } } while(0)
int main(void) {
    g_xbox_mem_offset=(ptrdiff_t)calloc(1,0x800000); CHECK(g_xbox_mem_offset!=0);
    bo3_menu_entry_start(); for(int i=0;i<4;i++) CHECK(hooks[i]!=NULL);
    recomp_env_set(RENV_HEADLESS,"0"); recomp_env_set(RENV_MENU_ENTRY,"1");
    g_esi=0x55ABC4; g_eax=0x55ABCC; g_esp=0x7FF000; g_ecx=99; g_edx=88;
    U16(0x55ABCA)=4;
    for(int i=0;i<4;i++) U32(0x55ABCC+i*8)=0x10000+i*4;
    hooks[0]();
    CHECK(U16(0x55ABCA)==5 && g_eax==0x700000);
    CHECK(g_ecx==99 && g_edx==88 && g_esp==0x7FF000);
    for(int i=0;i<4;i++) CHECK(U32(0x700000+i*8)==0x10000+i*4);
    uint32_t label=U32(0x700020);
    const char *text="IOS SETTINGS";
    for(unsigned i=0;i<=strlen(text);i++) CHECK(U16(label+i*2)==text[i]);
    U16(0x55ABC8)=4; g_eax=0xABCD0001; hooks[1](); CHECK(g_eax==0xABCD0000 && requested==1);
    U16(0x55ABC8)=3; g_eax=1; hooks[1](); CHECK(g_eax==1 && requested==1);
    recomp_env_set(RENV_MENU_ENTRY,"0"); U16(0x55ABCA)=4; g_eax=0x55ABCC; hooks[0](); CHECK(U16(0x55ABCA)==4);
    recomp_env_set(RENV_MENU_ENTRY,"1"); recomp_env_set(RENV_HEADLESS,"1"); hooks[0](); CHECK(U16(0x55ABCA)==4);
    recomp_env_set(RENV_HEADLESS,"0");
    /* Pause: original QUIT moves down; native row gets a private action code. */
    g_ebx=0x5593E4; U16(0x5593EA)=5; U8(0x559444)=0;
    U32(0x55940C)=0x123456; U32(0x559438)=5;
    hooks[2](); CHECK(U16(0x5593EA)==6);
    CHECK(U32(0x559414)==0x123456 && U32(0x55943C)==5 && U32(0x559438)==0x7A);
    g_esi=0x5593E4; g_edi=0x600000; U16(0x60004C)=1; U16(0x5593E8)=4;
    hooks[3](); CHECK(requested==2);
    U16(0x5593E8)=5; hooks[3](); CHECK(requested==2); /* Original Quit remains original. */
    U16(0x5593EA)=7; hooks[2](); CHECK(U16(0x5593EA)==7); /* No overflow. */
    U16(0x5593EA)=5; U8(0x559444)=1; hooks[2](); CHECK(U16(0x5593EA)==5); /* Alternate layout untouched. */
    free((void *)g_xbox_mem_offset);
    puts("Injected menu labels, actions, register preservation and bounds passed.");
    return 0;
}

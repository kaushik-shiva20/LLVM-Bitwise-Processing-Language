%{
#include <stdio.h>
#include <math.h>

#include "llvm-c/Core.h"

typedef enum
{
    TYPE_VAL=0,
    TYPE_MASK,
    TYPE_MAX
}eParamType;

typedef struct string_list_node_def {
    struct string_list_node_def *next;
    const char *str;
    LLVMValueRef llvmValueRef;
    LLVMValueRef llvmMaskRef;
    LLVMValueRef llvmStartPos;
    LLVMValueRef llvmNoOfBits;
    eParamType paramType;
} string_list_node;

typedef struct {
    string_list_node *head;
    string_list_node *tail;
} string_list;

typedef struct {
    LLVMValueRef val;
    LLVMValueRef NoOfBits;
} mBitSlice;
  
#include "p1.y.h"

%}

%option debug

%%

[ \t]         //ignore

in            { return IN; }
final         { return FINAL; }
none          { return NONE;  }
slice         {return SLICE;}
reduce        { return REDUCE;}
expand        { return EXPAND;}
[a-zA-Z]+     { yylval.param_str = strdup(yytext); return ID; }
[0-9]+        { yylval.val = atoi(yytext); return NUMBER; }

"["           { return LBRACKET; }
"]"           { return RBRACKET; }
"("           { return LPAREN; }
")"           { return RPAREN; }
"{"           {return LBRACE;}
"}"           {return RBRACE;}

"="           { return ASSIGN; }
"*"           { return MUL; }
"%"           { return MOD; }
"/"           { return DIV; }
"+"           { return PLUS; }
"-"           { return MINUS; }

"^"           { return XOR; }
"|"           { return OR; }
"&"           { return AND; }

"~"           { return INV; }
"!"           { return BINV; }


","           { return COMMA; }
"."           {return DOT;}
":"            {return COLON;}

\n            { return ENDLINE; }


"//".*\n      { }

.             { printf("\nDOT:%s File:%s line:%d\n",yytext,__FILE__ ,__LINE__); }
%%

int yywrap()
{
  return 1;
}

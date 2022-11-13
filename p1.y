%{
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include "llvm-c/Core.h"

#define MAX_32_BIT (~0u)
// Need for parser and scanner

int slice_id_cnt = 0;
char *slice_id_ptrs[100];//assuming max 100 slice id

extern FILE *yyin;
int yylex();
void yyerror(const char*);
int yyparse();
// Needed for LLVM
char* funName;
LLVMModuleRef M;
LLVMBuilderRef  Builder;

LLVMValueRef val_max_32_bit;

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

int bitslice_helper_cnt=0;
mBitSlice * mbitslice_helper_arr[100];

string_list * master_param_list;
string_list * master_slice_list;

 string_list* string_list_create() {
   string_list *list = (string_list *)malloc(sizeof(string_list));
   list->head = NULL;
   list->tail = NULL;
   return list;
 }

string_list_node * string_list_append(string_list *list, const char * str)
 {
   string_list_node *node = (string_list_node *)malloc(sizeof(string_list_node));
   node->str = str;
   node->next = NULL;
   node->llvmValueRef = LLVMConstInt(LLVMInt32Type(),0,0);
   node->llvmMaskRef= LLVMConstInt(LLVMInt32Type(),MAX_32_BIT,0);
   node->llvmStartPos=LLVMConstInt(LLVMInt32Type(),0,0);
   node->llvmNoOfBits=LLVMConstInt(LLVMInt32Type(),0,0);
   node->paramType = TYPE_MAX;
   if (list->tail) {
     list->tail->next = node;
     list->tail = node;
   } else {
     list->head = list->tail = node;
   }
   return node;
 }

string_list_node * string_list_search(string_list *list, const char * str)
 {
     string_list_node *tempnode=NULL;
     string_list_node *mRetNode=NULL;
     tempnode=list->head;
     while(tempnode != NULL)
     {
        if(!strcmp(tempnode->str, str))
        {
            mRetNode = tempnode;
            break;
        }
        tempnode = tempnode->next;
     }
     return mRetNode;
 }
 
%}

%union {
  string_list *params_list;
  mBitSlice * bitslicedef;
  char * param_str;
  int val;
  LLVMValueRef llvmValueRef;
  string_list_node *mstring_list_node_type;
}

%verbose
%define parse.trace

%type <params_list> params_list
%type <llvmValueRef> expr final
%type <bitslicedef> bitslice bitslice_list
%type <mstring_list_node_type> bitslice_lhs


%token IN FINAL SLICE
%token ERROR
%token <val> NUMBER
%token <param_str> ID
%token BINV INV PLUS MINUS XOR AND OR MUL DIV MOD
%token COMMA ENDLINE ASSIGN LBRACKET RBRACKET
%token LPAREN RPAREN NONE COLON DOT
%token REDUCE EXPAND LBRACE RBRACE

%precedence BINV
%precedence INV
%left PLUS MINUS OR
%left MUL DIV AND XOR MOD

%start program

%%

program: inputs statements_opt final
{
  YYACCEPT;
}
;

inputs:   IN params_list ENDLINE
{
  string_list_node *tmp = $2->head;
  int cnt=0;
  while(tmp)
    {
      cnt++;
      tmp = tmp->next;
    }
  LLVMTypeRef *paramTypes = (LLVMTypeRef *)malloc(sizeof(LLVMTypeRef)*cnt);
  for(int i=0; i<cnt; i++)
    paramTypes[i] = LLVMInt32Type();
  
  LLVMTypeRef IntFnTy = LLVMFunctionType(LLVMInt32Type(),paramTypes,cnt,0);

  // Make a void function named main (the start of the program!)
  LLVMValueRef Fn = LLVMAddFunction(M,funName,IntFnTy);

  // Add a basic block to main to hold new instructions
  LLVMBasicBlockRef BB = LLVMAppendBasicBlock(Fn,"entry");

  // Create a Builder object that will construct IR for us
  Builder = LLVMCreateBuilder();
  // Ask builder to place new instructions at end of the
  // basic block

  //Fetch function parameters and store it to the list
  tmp = $2->head;
  unsigned cnt1 = 0;
  while(cnt1<cnt)
  {
    tmp->llvmValueRef =  LLVMGetParam(Fn, cnt1);
    cnt1++;
    tmp = tmp->next;
  }
  LLVMPositionBuilderAtEnd(Builder,BB);

}
| IN NONE ENDLINE
{
  // Make a void function type with no arguments
  LLVMTypeRef IntFnTy = LLVMFunctionType(LLVMInt32Type(),NULL,0,0);

  // Make a void function named main (the start of the program!)
  LLVMValueRef Fn = LLVMAddFunction(M,funName,IntFnTy);

  // Add a basic block to main to hold new instructions
  LLVMBasicBlockRef BB = LLVMAppendBasicBlock(Fn,"entry");

  // Create a Builder object that will construct IR for us
  Builder = LLVMCreateBuilder();
  // Ask builder to place new instructions at end of the
  // basic block
  LLVMPositionBuilderAtEnd(Builder,BB);
}
;

params_list: ID
{
    //Add ID to master parameter list
    string_list_node * temp;
    temp = string_list_append(master_param_list,$1);
    temp->paramType = TYPE_VAL;
    $$ = master_param_list ;
}
| params_list COMMA ID
{
    //Add ID to master parameter list
    string_list_node * temp;
    temp=string_list_append(master_param_list,$3);
    temp->paramType = TYPE_VAL;
    $$ = master_param_list;
}
;

final: FINAL expr ENDLINE
{
   $$ = LLVMBuildRet(Builder,$2);
   return 0;
}
;

statements_opt: %empty
            | statements;

statements:   statement
            | statements statement 
;

statement: bitslice_lhs ASSIGN expr ENDLINE
{
    LLVMValueRef leftMask;
    LLVMValueRef leftVal;
    LLVMValueRef RightVal;
    LLVMValueRef tempSeg;
    string_list_node * temp;
    temp = $1;
    if(temp->paramType == TYPE_MASK)
    {
        leftVal = temp->llvmValueRef;
        tempSeg = LLVMBuildShl(Builder,$3,temp->llvmStartPos,"");
        RightVal = LLVMBuildAnd(Builder, tempSeg, temp->llvmMaskRef, "");
        leftMask = LLVMBuildXor(Builder, temp->llvmMaskRef, val_max_32_bit, "");
        leftVal = LLVMBuildAnd(Builder, leftVal, leftMask, "");
        temp->llvmValueRef = LLVMBuildOr(Builder, leftVal, RightVal, "");

    }else if(temp->paramType == TYPE_VAL)
    {
        temp->llvmValueRef = $3;
    }else
    {
        //TODO: error
    }
    temp->llvmMaskRef = val_max_32_bit;
    temp->llvmNoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    temp->paramType = TYPE_VAL;
}
| SLICE field_list ENDLINE
{
    string_list_node * temp;
    //LLVMValueRef tempmask;
    LLVMValueRef tempSeg;
    LLVMValueRef tempOne;
    tempOne = LLVMConstInt(LLVMInt32Type(),1,0);
    //Handling for slice a,b,c
    for(int i=0;i<slice_id_cnt;i++)
    {
        temp = string_list_search(master_slice_list,slice_id_ptrs[i]);
        if(temp == NULL)
        {
            return 1;
        }
        tempSeg = LLVMConstInt(LLVMInt32Type(),(slice_id_cnt-1-i),0);
        //tempmask = LLVMBuildShl(Builder,tempOne,tempSeg,"");
        temp->llvmMaskRef = LLVMBuildShl(Builder,tempOne,tempSeg,"");//LLVMBuildAnd(Builder, temp->llvmMaskRef, tempmask, "");
        temp->llvmStartPos = LLVMConstInt(LLVMInt32Type(),(slice_id_cnt-1-i),0);
        temp->llvmNoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    }
    slice_id_cnt = 0;
}
;


field_list : field_list COMMA field
           | field
;

field : ID COLON expr
{
    string_list_node * temp;
    //LLVMValueRef tempmask;
    LLVMValueRef tempOne;
    tempOne = LLVMConstInt(LLVMInt32Type(),1,0);
    temp = string_list_search(master_slice_list,$1);
    if(temp == NULL)
    {
        temp = string_list_append(master_slice_list,$1);
    }else
    {
        //already defined
    }
    temp->paramType = TYPE_MASK;
    //TODO: handle $3 > 32
    //tempmask = LLVMBuildShl(Builder,tempOne,$3,"");
    temp->llvmMaskRef = LLVMBuildShl(Builder,tempOne,$3,"");//LLVMBuildAnd(Builder,temp->llvmMaskRef,tempmask,"");
    temp->llvmStartPos = $3;
    temp->llvmNoOfBits = tempOne;
}
| ID LBRACKET expr RBRACKET COLON expr
{
    string_list_node * temp;
    LLVMValueRef tempmask;
    LLVMValueRef tempLSB;
    LLVMValueRef tempMSB;
    LLVMValueRef tempSeg;
    LLVMValueRef temp32;
    temp32 = LLVMConstInt(LLVMInt32Type(),32,0);
    tempLSB = $6;
    tempSeg = LLVMBuildAdd(Builder,$3,$6,"");
    tempMSB = LLVMBuildSub(Builder, temp32, tempSeg,"");
    LLVMValueRef tempSeg1;
    tempSeg1 = LLVMBuildLShr(Builder, val_max_32_bit,tempLSB,"");
    tempSeg1 = LLVMBuildShl(Builder,tempSeg1,tempLSB,"");
    tempSeg1 = LLVMBuildShl(Builder,tempSeg1,tempMSB,"");
    tempmask = LLVMBuildLShr(Builder, tempSeg1,tempMSB,"");

    temp = string_list_search(master_slice_list,$1);
    if(temp == NULL)
    {
        temp = string_list_append(master_slice_list,$1);
    }else
    {
        //already defined
    }
    temp->paramType = TYPE_MASK;
    temp->llvmStartPos = $6;
    temp->llvmNoOfBits = $3;
    temp->llvmMaskRef = tempmask;//LLVMBuildAnd(Builder,temp->llvmMaskRef,tempmask,"");
}
// 566 only below
| ID
{
    string_list_node * temp;
    temp = string_list_search(master_slice_list,$1);
    if(temp == NULL)
    {
        temp = string_list_append(master_slice_list,$1);
    }else
    {
        //already defined
    }
    temp->paramType = TYPE_MASK;
    slice_id_ptrs[slice_id_cnt]=$1;
    slice_id_cnt++;
};

expr: bitslice
{
    //mBitSlice * tempRet;
 //tempRet = $1;
 $$ = $1->val;
}
| expr PLUS expr {$$ = LLVMBuildAdd(Builder, $1, $3,"");}
| expr MINUS expr {$$ = LLVMBuildSub(Builder, $1, $3,"");}
| expr XOR expr {$$ = LLVMBuildXor(Builder, $1, $3,"");}
| expr AND expr {$$ = LLVMBuildAnd(Builder, $1, $3,"");}
| expr OR expr  {$$ = LLVMBuildOr(Builder, $1, $3,"");}
| INV expr      {$$ = LLVMBuildXor(Builder, $2, val_max_32_bit,""); }
| BINV expr     {LLVMValueRef temp = LLVMConstInt(LLVMInt32Type(),1,0);$$ =  LLVMBuildXor(Builder, $2,temp,"");} //flip LSB bit
| expr MUL expr {$$ = LLVMBuildMul(Builder, $1, $3,"");}
| expr DIV expr {$$ = LLVMBuildUDiv(Builder, $1, $3,"");}
| expr MOD expr {$$ = LLVMBuildURem(Builder, $1, $3,"");}
/* 566 only */
| REDUCE AND LPAREN expr RPAREN
{
  $$ = LLVMBuildICmp(Builder, LLVMIntEQ, $4, val_max_32_bit, "");
}
| REDUCE OR LPAREN expr RPAREN
{
  LLVMValueRef temp2 = LLVMConstInt(LLVMInt32Type(), 0, 0);
  $$ = LLVMBuildICmp(Builder, LLVMIntNE, $4, temp2, "");
}
| REDUCE XOR LPAREN expr RPAREN
{
  LLVMValueRef tempRet;
  LLVMValueRef tempOne;
  LLVMValueRef tempSeg1;
  LLVMValueRef tempSeg2;
  LLVMValueRef tempSeg3;
  tempRet = LLVMConstInt(LLVMInt32Type(), 0,0);
  tempOne = LLVMConstInt(LLVMInt32Type(), 1,0);
  for(int i=0;i<32;i++)
  {
      tempSeg1 = LLVMConstInt(LLVMInt32Type(), i,0);
      tempSeg2 = LLVMBuildLShr(Builder,$4,tempSeg1,"");
      tempSeg3 = LLVMBuildAnd(Builder, tempSeg2 , tempOne,"");
      tempRet = LLVMBuildXor(Builder, tempSeg3, tempRet, "");
  }
  $$ = tempRet;
}
| REDUCE PLUS LPAREN expr RPAREN
{
  LLVMValueRef tempRet;
  LLVMValueRef tempOne;
  LLVMValueRef tempSeg1;
  LLVMValueRef tempSeg2;
  LLVMValueRef tempSeg3;
  tempRet = LLVMConstInt(LLVMInt32Type(), 0,0);
  tempOne = LLVMConstInt(LLVMInt32Type(), 1,0);
  for(int i=0;i<32;i++)
  {
      tempSeg1 = LLVMConstInt(LLVMInt32Type(), i,0);
      tempSeg2 = LLVMBuildLShr(Builder,$4,tempSeg1,"");
      tempSeg3 = LLVMBuildAnd(Builder, tempSeg2 , tempOne,"");
      tempRet = LLVMBuildAdd(Builder, tempSeg3, tempRet, "");
  }
  $$ = tempRet;
}
| EXPAND LPAREN expr RPAREN
{
  LLVMValueRef temp1;
  LLVMValueRef temp2;
  LLVMValueRef tempIn;
  LLVMValueRef tempSeg1;
  temp1 = LLVMConstInt(LLVMInt32Type(),0,0);
  temp2 = LLVMConstInt(LLVMInt32Type(),1,0);
  tempIn = LLVMBuildAnd(Builder,$3,temp2,"");


  tempSeg1 = LLVMBuildICmp(Builder, LLVMIntEQ, tempIn, temp1, "");
  $$ = LLVMBuildSelect(Builder,tempSeg1, temp1,val_max_32_bit,"");
};

bitslice: ID
{
  // search if ID is defined
  string_list_node * temp;
  mBitSlice * tempRet=(mBitSlice *)malloc(sizeof(mBitSlice));
  tempRet->val = LLVMConstInt(LLVMInt32Type(),0,0);
  tempRet->NoOfBits = LLVMConstInt(LLVMInt32Type(),0,0);
  temp = string_list_search(master_param_list,$1);
  if(temp != NULL)
  {
      tempRet->val = temp->llvmValueRef;
      tempRet->NoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
      $$ = tempRet;

  }else
  {
      //bitslice not found
      //TODO: error
  }
}
| NUMBER
{
    mBitSlice * tempRet=(mBitSlice *)malloc(sizeof(mBitSlice));
    tempRet->val = LLVMConstInt(LLVMInt32Type(), $1, 0);
    tempRet->NoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    $$ = tempRet;
}
| bitslice_list
{
    //now it's just a value
    mBitSlice * tempRet=(mBitSlice *)malloc(sizeof(mBitSlice));
    tempRet->val = $1->val;
    tempRet->NoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    $$ = tempRet;
}
| LPAREN expr RPAREN
{
    //TODO: check this (expr) bitslice not defined
    mBitSlice * tempRet=(mBitSlice *)malloc(sizeof(mBitSlice));
    tempRet->val = $2;
    tempRet->NoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    $$ = tempRet;
}
| bitslice NUMBER
{
    LLVMValueRef tempSeg1;
    LLVMValueRef tempSeg2;
    //LLVMValueRef tempSeg3;
    mBitSlice * tempRet=(mBitSlice *)malloc(sizeof(mBitSlice));
    mBitSlice * tempIn;
    int tempNumber;
    tempIn = $1;
    tempNumber = $2;
    if(tempNumber>=32)
    {
        tempNumber = 31;
    }


    tempSeg1 = LLVMConstInt(LLVMInt32Type(), tempNumber, 0);
    /*tempSeg2 = LLVMBuildShl(Builder,LLVMConstInt(LLVMInt32Type(), 1, 0),tempSeg1,"");
    tempSeg3 = LLVMBuildAnd(Builder, tempIn->val, tempSeg2, "");
    tempRet->val = LLVMBuildLShr(Builder,tempSeg3,tempSeg1,"");*/
    tempSeg2 = LLVMBuildLShr(Builder, tempIn->val, tempSeg1, "" );
    tempRet->val = LLVMBuildAnd(Builder, tempSeg2, LLVMConstInt(LLVMInt32Type(), 1, 0),"");
    tempRet->NoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    $$ = tempRet;
}
| bitslice DOT ID
{
    // search if ID is defined
    LLVMValueRef tempSeg1;
    string_list_node * temp;
    mBitSlice * tempRet=(mBitSlice *)malloc(sizeof(mBitSlice));
    mBitSlice * tempIn;
    tempIn = $1;
    temp = string_list_search(master_slice_list,$3);
    if(temp != NULL)
    {
        tempSeg1 = LLVMBuildAnd(Builder, tempIn->val, temp->llvmMaskRef, "");
        tempRet->val = LLVMBuildLShr(Builder,tempSeg1,temp->llvmStartPos,"");
        tempRet->NoOfBits = temp->llvmNoOfBits;
        $$ = tempRet;
    }else
    {
        //TODO: error
    }
}
// 566 only
| bitslice LBRACKET expr RBRACKET
{
    mBitSlice * tempReturn=(mBitSlice *)malloc(sizeof(mBitSlice));
    LLVMValueRef tempMask;
    LLVMValueRef tempRet;
    LLVMValueRef tempOne;
    mBitSlice * tempIn;
    tempIn = $1;
    tempOne = LLVMConstInt(LLVMInt32Type(),1,0);
    tempMask = LLVMBuildShl(Builder,tempOne,$3,"");
    tempRet = LLVMBuildAnd(Builder, tempIn->val, tempMask, "");
    tempReturn->val = LLVMBuildLShr(Builder,tempRet, $3,"");
    tempReturn->NoOfBits = tempOne;
    $$ = tempReturn;

}
| bitslice LBRACKET expr COLON expr RBRACKET
{
    mBitSlice * tempReturn=(mBitSlice *)malloc(sizeof(mBitSlice));
    LLVMValueRef tempmask;
    LLVMValueRef tempLSB;
    LLVMValueRef tempMSB;
    mBitSlice * tempIn;
    tempIn = $1;
    tempLSB = $5;
    LLVMValueRef tempSeg1;
    tempSeg1 = LLVMConstInt(LLVMInt32Type(),31,0);
    tempMSB = LLVMBuildSub(Builder, tempSeg1, $3,"");
    tempSeg1 = LLVMBuildLShr(Builder,val_max_32_bit,tempLSB,"");
    tempSeg1 = LLVMBuildShl(Builder, tempSeg1,tempLSB,"");
    tempSeg1 = LLVMBuildShl(Builder,tempSeg1,tempMSB,"");
    tempmask = LLVMBuildLShr(Builder,tempSeg1,tempMSB,"");

    tempSeg1 = LLVMBuildAnd(Builder, tempIn->val, tempmask, "");
    tempReturn->val = LLVMBuildLShr(Builder,tempSeg1,tempLSB,"");
    tempSeg1 = LLVMBuildSub(Builder, $3, $5, "");
    LLVMValueRef tempOne;
    tempOne = LLVMConstInt(LLVMInt32Type(),1,0);
    tempReturn->NoOfBits = LLVMBuildAdd(Builder,tempSeg1,tempOne,"");
    $$ = tempReturn;
};

bitslice_list: LBRACE bitslice_list_helper RBRACE
{

    mBitSlice * temp =(mBitSlice *)malloc(sizeof(mBitSlice));
    LLVMValueRef tempShift;
    LLVMValueRef tempmask;
    LLVMValueRef tempShiftVal;
    LLVMValueRef tempVal;
    tempShift = LLVMConstInt(LLVMInt32Type(),0,0);
    temp->val = LLVMConstInt(LLVMInt32Type(),0,0);
    LLVMValueRef temp32;
    temp32 = LLVMConstInt(LLVMInt32Type(),32,0);
    LLVMValueRef tempSeg1;
    for(int i=(bitslice_helper_cnt-1);i>=0;i--)
    {

        tempShiftVal = LLVMBuildSub(Builder, temp32, mbitslice_helper_arr[i]->NoOfBits,"");
        tempSeg1 = LLVMBuildShl(Builder,val_max_32_bit,tempShiftVal,"");
        tempmask = LLVMBuildLShr(Builder,tempSeg1,tempShiftVal,"");
        tempVal = LLVMBuildAnd(Builder, mbitslice_helper_arr[i]->val, tempmask,"");
        tempSeg1 = LLVMBuildShl(Builder,tempVal,tempShift,"");
        temp->val = LLVMBuildOr(Builder, temp->val, tempSeg1,"");
        tempShift = LLVMBuildAdd(Builder, tempShift, mbitslice_helper_arr[i]->NoOfBits,"");
    }
    temp->NoOfBits = tempShift;
    bitslice_helper_cnt = 0;
    $$ = temp;

}
;

bitslice_list_helper:  bitslice
{
    mbitslice_helper_arr[bitslice_helper_cnt] = $1;
    bitslice_helper_cnt++;
}
| bitslice_list_helper COMMA bitslice
{
    mbitslice_helper_arr[bitslice_helper_cnt] = $3;
    bitslice_helper_cnt++;
}
;

bitslice_lhs: ID
{
    string_list_node * temp;
    temp = string_list_search(master_param_list,$1);
    if(temp == NULL)
    {
        temp = string_list_append(master_param_list, $1);
    }

    temp->paramType = TYPE_VAL;
    temp->llvmMaskRef = val_max_32_bit;
    temp->llvmStartPos = LLVMConstInt(LLVMInt32Type(),0,0);
    temp->llvmNoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    $$ = temp;
}
| bitslice_lhs NUMBER
{
    string_list_node * temp;
    int tempNumber;
    temp = $1;
    tempNumber = $2;
    temp->paramType = TYPE_MASK;

    if(tempNumber>=32)
    {
        tempNumber = 31;
    }

    temp->llvmMaskRef = LLVMBuildAnd(Builder,LLVMBuildShl(Builder,LLVMConstInt(LLVMInt32Type(),1,0),LLVMConstInt(LLVMInt32Type(),tempNumber,0),""),temp->llvmMaskRef, "");
    temp->llvmStartPos = LLVMConstInt(LLVMInt32Type(),tempNumber,0);
    temp->llvmNoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    $$ = temp;
}
| bitslice_lhs DOT ID
{
    string_list_node * tempID;
    string_list_node * templhs;
    templhs = $1;
    tempID = string_list_search(master_slice_list,$3);
    if(tempID != NULL)
    {
       templhs->llvmMaskRef = LLVMBuildAnd(Builder,templhs->llvmMaskRef, LLVMBuildShl(Builder,tempID->llvmMaskRef,templhs->llvmStartPos,""), "");
       templhs->paramType = TYPE_MASK;
       templhs->llvmStartPos = LLVMBuildAdd(Builder,templhs->llvmStartPos,tempID->llvmStartPos,"");
       templhs->llvmNoOfBits = tempID->llvmNoOfBits;
    }else
    {
        //ID not found
        //TODO:error
    }
    $$ = templhs;
}
// 566 only
| bitslice_lhs LBRACKET expr RBRACKET
{
    string_list_node * templhs;
    //TODO: handle $3 > 32
    templhs= $1;
    templhs->paramType = TYPE_MASK;
    templhs->llvmMaskRef = LLVMBuildAnd(Builder,LLVMBuildShl(Builder,LLVMConstInt(LLVMInt32Type(),1,0),$3,""),templhs->llvmMaskRef, "");
    templhs->llvmStartPos = $3;
    templhs->llvmNoOfBits = LLVMConstInt(LLVMInt32Type(),1,0);
    $$ = templhs;
}
| bitslice_lhs LBRACKET expr COLON expr RBRACKET
{
    string_list_node * templhs;
    LLVMValueRef tempmask;
    LLVMValueRef tempLSB;
    LLVMValueRef tempMSB;
    LLVMValueRef tempNoOfBits;
    tempLSB = $5;
    tempMSB = LLVMBuildSub(Builder, LLVMConstInt(LLVMInt32Type(),31,0), $3,"");
    tempmask = LLVMBuildLShr(Builder,LLVMBuildShl(Builder,LLVMBuildShl(Builder,LLVMBuildLShr(Builder,LLVMConstInt(LLVMInt32Type(), MAX_32_BIT, 0),tempLSB,""),tempLSB,""),tempMSB,""),tempMSB,"");

    templhs = $1;
    templhs->paramType = TYPE_MASK;
    templhs->llvmMaskRef = LLVMBuildAnd(Builder,tempmask,templhs->llvmMaskRef, "");
    templhs->llvmStartPos = $5;
    tempNoOfBits = LLVMBuildSub(Builder, $3,$5,"");
    templhs->llvmNoOfBits = tempNoOfBits;
    $$ = templhs;
};


%%

LLVMModuleRef parseP1File(const char* InputFilename)
{
  // Figure out function name
  char *pos = (char *)strrchr(InputFilename,'/');
  if (pos)
    funName = strdup(pos+1);
  else 
    funName = strdup(InputFilename);
  pos = strchr(funName,'.');
  if (pos) *pos = 0;

  // Make Module
  M = LLVMModuleCreateWithName(funName);
  
  yyin = fopen(InputFilename,"r");
  master_param_list = string_list_create();
  master_slice_list = string_list_create();
  val_max_32_bit = LLVMConstInt(LLVMInt32Type(), MAX_32_BIT, 0);
  yydebug = 1;
  if (yyparse() != 0) {
    // errors, so discard module
    return NULL;
  } else {
    LLVMDumpModule(M);
    return M;
  }
}

void yyerror(const char* msg)
{
  printf("%s\n",msg);
}

bool getBit(int val, int bit_pos)
{
  bool mRet;
  mRet = (bool)((val & (1u << bit_pos)) >> bit_pos);
  return  mRet;
}

int setBit(int val, int bit_pos, bool bit_val)
{
  val &= (~(1u << bit_pos));
          if(bit_val == 1u)
          {
            val |= (1u << bit_pos);
          }
  return val;
}
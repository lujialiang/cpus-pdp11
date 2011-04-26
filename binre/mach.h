
enum {
	M_NOP,
	M_HALT,
	M_WAIT,
	M_RESET,
	M_LOAD,
	M_LOADSR,
	M_LOADI,
	M_LOADIND,
	M_LOADINDPM,
	M_LOADPSW,
	M_STOREIND,
	M_STOREINDPM,
	M_STOREPSW,
	M_ADD,
	M_ADDI,
	M_ADDC,
	M_SUB,
	M_SUBI,
	M_SUBC,
	M_FLAGS,
	M_FLAGMUX,
	M_BR,
	M_JMP,
	M_SWAB,
	M_SHIFT,
	M_SHIFT32,
	M_ASR,
	M_ROTATE,
	M_AND,
	M_OR,
	M_NOT,
	M_SXT,
	M_DIV,
	M_MUL,

	M_LOADB = 128,
	M_LOADIB,
	M_LOADINDB,
	M_STOREINDB,
	M_ADDCB,
	M_ADDIB,
	M_SUBIB,
	M_NOTB,
	M_ANDB,
	M_ORB,
	M_SUBB,
};

enum {
	R_S0 = 8,
	R_S1 = 9,
	R_S2 = 10,
	R_D0 = 11,
	R_D1 = 12,
	R_D2 = 13,
	R_R0 = 14,
	R_R1 = 15,
};

enum {
	B_ALWAYS = 0,
	B_NE,
	B_EQ,
	B_GE,
	B_LT,
	B_GT,
	B_LE,
	B_PL,
	B_MI,
	B_HI,
	B_LO,
	B_VC,
	B_VS,
	B_CC,
	B_CS,
	B_REGZERO
};

enum {
	FM_ADC,
	FM_ADD,
	FM_ASH,
	FM_ASHC,
	FM_ASL,
        FM_ASR,
        FM_BIC,
        FM_BIS,
        FM_BIT,
        FM_CLR,
        FM_CMP,
        FM_COM,
        FM_DEC,
	FM_DIV,
	FM_INC,
	FM_MFPI,
	FM_MFPD,
	FM_MFPS,
	FM_MOV,
	FM_MTPS,
	FM_MTPD,
	FM_MUL,
	FM_NEG,
	FM_ROL,
	FM_ROR,
	FM_SBC,
	FM_SUB,
	FM_SXT,
	FM_TST,
	FM_XOR,

	FM_ADCB = 128,
        FM_ASLB,
        FM_ASRB,
        FM_BICB,
        FM_BISB,
        FM_BITB,
        FM_CLRB,
        FM_CMPB,
        FM_COMB,
        FM_DECB,
	FM_INCB,
	FM_MOVB,
	FM_NEGB,
	FM_ROLB,
	FM_RORB,
	FM_SBCB,
	FM_SWAB,
	FM_TSTB,
};
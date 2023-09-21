* comm - copmare 2 sorted file
*
* Itagaki Fumihiko 15-Jan-95  Create.
* 1.0
*
* Usage: comm [ -123bsBCZ ] [ -- ] <file1> <file2>

.include doscall.h
.include chrcode.h
.include stat.h

.xref DecodeHUPAIR
.xref issjis
.xref strlen
.xref strfor1
.xref memcmp
.xref memmovi
.xref strip_excessive_slashes

STACKSIZE	equ	2048

READSIZE	equ	8192
INPBUFSIZE_MIN	equ	258
OUTBUF_SIZE	equ	8192

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_1		equ	0	*  -1
FLAG_2		equ	1	*  -2
FLAG_3		equ	2	*  -3
FLAG_b		equ	3	*  -b
FLAG_s		equ	4	*  -s
FLAG_B		equ	5	*  -B
FLAG_C		equ	6	*  -C
FLAG_Z		equ	7	*  -Z


.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom(pc),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.L : フラグ
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		move.b	1(a0),d0
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		moveq	#FLAG_1,d1
		cmp.b	#'1',d0
		beq	set_option

		moveq	#FLAG_2,d1
		cmp.b	#'2',d0
		beq	set_option

		moveq	#FLAG_3,d1
		cmp.b	#'3',d0
		beq	set_option

		moveq	#FLAG_b,d1
		cmp.b	#'b',d0
		beq	set_option

		moveq	#FLAG_s,d1
		cmp.b	#'s',d0
		beq	set_option

		cmp.b	#'B',d0
		beq	option_B_found

		cmp.b	#'C',d0
		beq	option_C_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

option_B_found:
		bclr	#FLAG_C,d5
		bset	#FLAG_B,d5
		bra	set_option_done

option_C_found:
		bclr	#FLAG_B,d5
		bset	#FLAG_C,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
		subq.l	#2,d7
		blo	too_few_args
		bhi	too_many_args
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin
		bmi	move_stdin_done

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
move_stdin_done:
	*
	*  入力をオープン
	*
		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1
		lea	file1(pc),a2
		bsr	open_input
		movea.l	a1,a0
		lea	file2(pc),a2
		bsr	open_input
	*
	*  出力をチェック
	*
		moveq	#1,d0
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering
		beq	check_output_done		*  -- block device

		*  character device
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	check_output_done

		*  cooked character device
		btst	#FLAG_B,d5
		bne	check_output_done

		bset	#FLAG_C,d5			*  改行を変換する
check_output_done:
	*
	*  出力バッファを確保する
	*
		tst.b	do_buffering
		beq	outbuf_ok

		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outbuf_top
		move.l	d0,outbuf_ptr
outbuf_ok:
	*
	*  入力バッファを確保する
	*
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		move.l	d0,d1
		lsr.l	#1,d1
		cmp.l	#INPBUFSIZE_MIN,d1
		blo	insufficient_memory

		bsr	malloc
		bmi	insufficient_memory

		move.l	d1,file1+fd_bufsize
		move.l	d1,file2+fd_bufsize
		move.l	d0,file1+fd_buftop
		move.l	d0,file1+fd_bufptr
		add.l	d1,d0
		move.l	d0,file2+fd_buftop
		move.l	d0,file2+fd_bufptr
	*
	*  メイン処理
	*
		bsr	comm
		bsr	flush_outbuf
		moveq	#0,d0
exit_program:
		move.w	d0,-(a7)
		move.l	stdin,d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
		addq.l	#4,a7
exit_program_1:
		DOS	_EXIT2

too_many_args:
		lea	msg_too_many_args(pc),a0
		bra	werror_usage

too_few_args:
		lea	msg_too_few_args(pc),a0
werror_usage:
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d0
		bra	exit_program
****************************************************************
open_input:
		move.l	a0,fd_pathname(a2)
		cmpi.b	#'-',(a0)
		bne	open_file

		tst.b	1(a0)
		bne	open_file

		lea	msg_stdin(pc),a0
		move.l	stdin,d0
		bra	input_open

open_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
input_open:
		tst.l	d0
		bmi	open_input_fail

		move.w	d0,fd_handle(a2)
		btst	#FLAG_Z,d5
		sne	fd_eof_ctrlz(a2)
		sf	fd_eof_ctrld(a2)
		bsr	is_chrdev
		beq	input_open_1			*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	input_open_1

		st	fd_eof_ctrlz(a2)
		st	fd_eof_ctrld(a2)
input_open_1:
		clr.l	fd_bufremain(a2)
		sf	fd_eof(a2)
		rts

open_input_fail:
		lea	msg_open_fail(pc),a2
		bsr	werror_myname_word_colon_msg
		moveq	#2,d0
		bra	exit_program
****************************************************************
* comm
****************************************************************
comm:
comm_loop:
		lea	file1(pc),a2
		bsr	getline
		lea	file2(pc),a2
		bsr	getline
		tst.l	file1+fd_linesize
		beq	comm_file1_eof

		tst.l	file2+fd_linesize
		beq	comm_file2_eof
comm_compare:
		movea.l	file1+fd_linetop,a0
		movea.l	file2+fd_linetop,a1
		move.l	file1+fd_linesize,d0
		move.l	file2+fd_linesize,d1
		cmp.l	d0,d1
		bhi	compare_file1_shorter_than_file2
		blo	compare_file2_shorter_than_file1

		bsr	memcmp
		bra	comm_compare_1

compare_file1_shorter_than_file2:
		bsr	memcmp
		bne	comm_compare_1
		bra	comm_output_file1

compare_file2_shorter_than_file1:
		move.l	d1,d0
		bsr	memcmp
		bne	comm_compare_1
		bra	comm_output_file2

comm_compare_1:
		blo	comm_output_file1
		bhi	comm_output_file2

		btst	#FLAG_3,d5
		bne	comm_loop

		moveq	#FLAG_1,d0
		bsr	put_tab
		moveq	#FLAG_2,d0
		bsr	put_tab
		movea.l	file1+fd_linetop,a0
		move.l	file1+fd_linesize,d1
		bsr	output
		btst	#FLAG_b,d5
		beq	comm_loop

		moveq	#FLAG_1,d0
		bsr	put_tab
		moveq	#FLAG_2,d0
		bsr	put_tab
		movea.l	file2+fd_linetop,a0
		move.l	file2+fd_linesize,d1
		bsr	output
		bra	comm_loop

comm_file1_eof:
		tst.l	file2+fd_linesize
		beq	comm_done
comm_output_file2:
		btst	#FLAG_2,d5
		bne	comm_file2_next

		moveq	#FLAG_1,d0
		bsr	put_tab
		movea.l	file2+fd_linetop,a0
		move.l	file2+fd_linesize,d1
		bsr	output
comm_file2_next:
		lea	file2(pc),a2
		bsr	getline
		tst.l	file2+fd_linesize
		beq	comm_file2_eof

		tst.l	file1+fd_linesize
		beq	comm_output_file2
		bra	comm_compare

comm_file2_eof:
		tst.l	file1+fd_linesize
		beq	comm_done
comm_output_file1:
		btst	#FLAG_1,d5
		bne	comm_file1_next

		movea.l	file1+fd_linetop,a0
		move.l	file1+fd_linesize,d1
		bsr	output
comm_file1_next:
		lea	file1(pc),a2
		bsr	getline
		tst.l	file1+fd_linesize
		beq	comm_file1_eof

		tst.l	file2+fd_linesize
		beq	comm_output_file1
		bra	comm_compare

comm_done:
output_done:
		rts
*****************************************************************
output:
output_loop:
		subq.l	#1,d1
		bcs	output_done

		move.b	(a0)+,d0
		btst	#FLAG_C,d5
		beq	output_4

			cmp.b	#CR,d0
			bne	output_3

				tst.l	d1
				beq	output_4

				cmpi.b	#LF,(a0)
				bne	output_4

				bsr	putc
				subq.l	#1,d1
				move.b	(a0)+,d0
				bra	output_4

output_3:
			cmp.b	#LF,d0
			bne	output_4

				moveq	#CR,d0
				bsr	putc
				moveq	#LF,d0
output_4:
		bsr	putc
		bra	output_loop
*****************************************************************
getline:
		clr.l	fd_linesize(a2)
getline_loop:
		movea.l	fd_bufptr(a2),a0
		subq.l	#1,fd_bufremain(a2)
		bcc	getc_get1

		tst.b	fd_eof(a2)
		bne	getc_eof

		move.l	fd_buftop(a2),d0
		add.l	fd_bufsize(a2),d0
		sub.l	a0,d0
		bne	getc_read

		movea.l	fd_buftop(a2),a0
		move.l	fd_linesize(a2),d0
		beq	getline_gb_4

		movea.l	fd_bufptr(a2),a1
		suba.l	d0,a1
		cmpa.l	a0,a1
		beq	getline_gb_3

		bsr	memmovi
		bra	getline_gb_4

getline_gb_3:
		adda.l	d0,a0
getline_gb_4:
		move.l	a0,fd_bufptr(a2)
		move.l	fd_buftop(a2),d0
		add.l	fd_bufsize(a2),d0
		sub.l	a0,d0
		beq	insufficient_memory
getc_read:
		cmp.l	#READSIZE,d0
		bls	getc_read_1

		move.l	#READSIZE,d0
getc_read_1:
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		move.w	fd_handle(a2),-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,fd_bufremain(a2)
		bmi	read_fail

		tst.b	fd_eof_ctrlz(a2)
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	fd_eof_ctrld(a2)
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		subq.l	#1,fd_bufremain(a2)
		bcs	getc_eof
getc_get1:
		moveq	#0,d0
		move.b	(a0)+,d0
		move.l	a0,fd_bufptr(a2)
		addq.l	#1,fd_linesize(a2)
		cmp.b	#LF,d0
		bne	getline_loop
getline_done:
		move.l	fd_bufptr(a2),d0
		sub.l	fd_linesize(a2),d0
		move.l	d0,fd_linetop(a2)
		rts

getc_eof:
		st	fd_eof(a2)
		clr.l	fd_bufremain(a2)
		clr.l	fd_linesize(a2)
		bra	getline_done

read_fail:
		movea.l	fd_pathname(a2),a0
		lea	msg_read_fail(pc),a2
		bsr	werror_myname_word_colon_msg
		bra	exit_3
*****************************************************************
trunc:
		move.l	fd_bufremain(a2),d1
		beq	trunc_done

		movea.l	fd_bufptr(a2),a1
trunc_find_loop:
		cmp.b	(a1)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
trunc_done:
		rts

trunc_found:
		subq.l	#1,a1
		move.l	a1,d0
		sub.l	a0,d0
		move.l	d0,fd_bufremain(a2)
trunc_eof:
		st	fd_eof(a2)
		rts
*****************************************************************
put_tab:
		btst	#FLAG_s,d5
		bne	put_tab_return

		btst	d0,d5
		bne	put_tab_return

		moveq	#HT,d0
putc:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering
		bne	putc_buffering

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail
		bra	putc_done

putc_buffering:
		tst.l	outbuf_free
		bne	putc_buffering_1

		bsr	flush_outbuf
putc_buffering_1:
		movea.l	outbuf_ptr,a0
		move.b	d0,(a0)+
		move.l	a0,outbuf_ptr
		subq.l	#1,outbuf_free
putc_done:
		movem.l	(a7)+,d0/a0
put_tab_return:
		rts
*****************************************************************
flush_outbuf:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering
		beq	flush_return

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free,d0
		beq	flush_return

		move.l	d0,-(a7)
		move.l	outbuf_top,-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blo	write_fail

		movea.l	outbuf_top,a0
		move.l	a0,outbuf_ptr
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free
flush_return:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
insufficient_memory:
		lea	msg_no_memory(pc),a0
		bsr	werror_myname_and_msg
		bra	exit_3
*****************************************************************
write_fail:
		bsr	werror_myname
		lea	msg_write_fail(pc),a0
		bsr	werror
exit_3:
		moveq	#3,d0
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
werror_myname_word_colon_msg:
		bsr	werror_myname_and_msg
		move.l	a0,-(a7)
		lea	str_colon(pc),a0
		bsr	werror
		movea.l	a2,a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
is_chrdev:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## comm 1.0 ##  Copyright(C)1995 by Itagaki Fumihiko',0

msg_myname:		dc.b	'comm'
str_colon:		dc.b	': ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_too_few_args:	dc.b	'引数が足りません',0
msg_too_many_args:	dc.b	'引数が多過ぎます',0
msg_open_fail:		dc.b	'オープンできません',CR,LF,0
msg_read_fail:		dc.b	'入力エラー',CR,LF,0
msg_write_fail:		dc.b	'出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_usage:		dc.b	CR,LF
			dc.b	'使用法:  comm [-123bsBCZ] [--] <file1> <file2>',CR,LF,0
*****************************************************************
.offset 0
fd_pathname:	ds.l	1
fd_bufsize:	ds.l	1
fd_buftop:	ds.l	1
fd_bufptr:	ds.l	1
fd_bufremain:	ds.l	1
fd_linetop:	ds.l	1
fd_linesize:	ds.l	1
fd_handle:	ds.w	1
fd_eof:		ds.b	1
fd_eof_ctrlz:	ds.b	1
fd_eof_ctrld:	ds.b	1
fd_pad:		ds.b	1
fd_size:

.bss
.even
stdin:				ds.l	1
file1:				ds.l	fd_size
file2:				ds.l	fd_size
outbuf_top:			ds.l	1
outbuf_ptr:			ds.l	1
outbuf_free:			ds.l	1
do_buffering:			ds.b	1
.even
			ds.b	STACKSIZE
.even
stack_bottom:
*****************************************************************

.end start

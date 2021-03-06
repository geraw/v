/*

regex 0.9e

Copyright (c) 2019-2020 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains regex module

Know limitation:
- find is implemented in a trivial way
- not full compliant PCRE
- not compliant POSIX ERE


*/
module regex
import strings

pub const(
	v_regex_version = "0.9e"      // regex module version

	max_code_len     = 256        // default small base code len for the regex programs
	max_quantifier   = 1073741824 // default max repetitions allowed for the quantifiers = 2^30

	// spaces chars (here only westerns!!) TODO: manage all the spaces from unicode
	spaces = [` `, `\t`, `\n`, `\r`, `\v`, `\f`]
	// new line chars for now only '\n'
	new_line_list = [`\n`,`\r`]

	// Results
	no_match_found          = -1

	// Errors
	compile_ok              =  0   // the regex string compiled, all ok
	err_char_unknown        = -2   // the char used is unknow to the system
	err_undefined           = -3   // the compiler symbol is undefined
	err_internal_error      = -4   // Bug in the regex system!!
	err_cc_alloc_overflow   = -5   // memory for char class full!!
	err_syntax_error        = -6   // syntax error in regex compiling
	err_groups_overflow     = -7   // max number of groups reached
	err_groups_max_nested   = -8   // max number of nested group reached
	err_group_not_balanced  = -9   // group not balanced
	err_group_qm_notation   = -10  // group invalid notation
)

const(
	//*************************************
	// regex program instructions
	//*************************************
	ist_simple_char  = u32(0x7FFFFFFF)   // single char instruction, 31 bit available to char

	// char class 11 0100 AA xxxxxxxx
	// AA = 00  regular class
	// AA = 01  Negated class ^ char
	ist_char_class       = 0xD1000000   // MASK
	ist_char_class_pos   = 0xD0000000   // char class normal [abc]
	ist_char_class_neg   = 0xD1000000   // char class negate [^abc]

	// dot char        10 0110 xx xxxxxxxx
	ist_dot_char         = 0x98000000   // match any char except \n

	// backslash chars 10 0100 xx xxxxxxxx
	ist_bsls_char        = 0x90000000   // backslash char

	// OR |            10 010Y xx xxxxxxxx
	ist_or_branch        = 0x91000000   // OR case

	// groups          10 010Y xx xxxxxxxx
	ist_group_start      = 0x92000000   // group start (
	ist_group_end        = 0x94000000   // group end   )

	// control instructions
	ist_prog_end         = u32(0x88000000)      //10 0010 xx xxxxxxxx
	//*************************************
)

/*

General Utilities

*/
// utf8util_char_len calculate the length in bytes of a utf8 char
[inline]
fn utf8util_char_len(b byte) int {
	return (( 0xe5000000 >> (( b >> 3 ) & 0x1e )) & 3 ) + 1
}

// get_char get a char from position i and return an u32 with the unicode code
[inline]
fn (re RE) get_char(in_txt string, i int) (u32,int) {
	// ascii 8 bit
	if (re.flag & f_bin) !=0 ||
		in_txt.str[i] & 0x80 == 0
	{
		return u32(in_txt.str[i]), 1
	}
	// unicode char
	char_len := utf8util_char_len(in_txt.str[i])
	mut tmp := 0
	mut ch := u32(0)
	for tmp < char_len {
		ch = (ch << 8) | in_txt.str[i+tmp]
		tmp++
	}
	return ch,char_len
}

// get_charb get a char from position i and return an u32 with the unicode code
[inline]
fn (re RE) get_charb(in_txt byteptr, i int) (u32,int) {
	// ascii 8 bit
	if (re.flag & f_bin) !=0 ||
		in_txt[i] & 0x80 == 0
	{
		return u32(in_txt[i]), 1
	}
	// unicode char
	char_len := utf8util_char_len(in_txt[i])
	mut tmp := 0
	mut ch := u32(0)
	for tmp < char_len {
		ch = (ch << 8) | in_txt[i+tmp]
		tmp++
	}
	return ch,char_len
}

[inline]
fn is_alnum(in_char byte) bool {
	mut tmp := in_char - `A`
	if tmp >= 0x00 && tmp <= 25 { return true }
	tmp = in_char - `a`
	if tmp >= 0x00 && tmp <= 25 { return true }
	tmp = in_char - `0`
	if tmp >= 0x00 && tmp <= 9  { return true }
	if tmp == `_` { return true }
	return false
}

[inline]
fn is_not_alnum(in_char byte) bool {
	return !is_alnum(in_char)
}

[inline]
fn is_space(in_char byte) bool {
	return in_char in spaces
}

[inline]
fn is_not_space(in_char byte) bool {
	return !is_space(in_char)
}

[inline]
fn is_digit(in_char byte) bool {
	tmp := in_char - `0`
	return tmp <= 0x09 && tmp >= 0
}

[inline]
fn is_not_digit(in_char byte) bool {
	return !is_digit(in_char)
}

[inline]
fn is_wordchar(in_char byte) bool {
	return is_alnum(in_char) || in_char == `_`
}

[inline]
fn is_not_wordchar(in_char byte) bool {
	return !is_alnum(in_char)
}

[inline]
fn is_lower(in_char byte) bool {
	tmp := in_char - `a`
	return  tmp >= 0x00 && tmp <= 25
}

[inline]
fn is_upper(in_char byte) bool {
	tmp := in_char - `A`
	return  tmp >= 0x00 && tmp <= 25
}

pub fn (re RE) get_parse_error_string(err int) string {
	match err {
		compile_ok             { return "compile_ok" }
		no_match_found         { return "no_match_found" }
		err_char_unknown       { return "err_char_unknown" }
		err_undefined          { return "err_undefined" }
		err_internal_error     { return "err_internal_error" }
		err_cc_alloc_overflow  { return "err_cc_alloc_overflow" }
		err_syntax_error       { return "err_syntax_error" }
		err_groups_overflow    { return "err_groups_overflow" }
		err_groups_max_nested  { return "err_groups_max_nested" }
		err_group_not_balanced { return "err_group_not_balanced" }
		err_group_qm_notation  { return "err_group_qm_notation" }
		else { return "err_unknown" }
	}
}

// utf8_str convert and utf8 sequence to a printable string
[inline]
fn utf8_str(ch u32) string {
	mut i := 4
	mut res := ""
	for i > 0 {
		v := byte((ch >> ((i-1)*8)) & 0xFF)
		if v != 0{
			res += "${v:1c}"
		}
		i--
	}
	return res
}

// simple_log default log function
fn simple_log(txt string) {
	print(txt)
}

/******************************************************************************
*
* Token Structs
*
******************************************************************************/
pub type FnValidator fn (byte) bool
struct Token{
mut:
	ist u32 = u32(0)

	// char
	ch u32                 = u32(0)  // char of the token if any
	ch_len byte            = byte(0) // char len

	// Quantifiers / branch
	rep_min         int    = 0     // used also for jump next in the OR branch [no match] pc jump
	rep_max         int    = 0     // used also for jump next in the OR branch [   match] pc jump
	greedy          bool   = false // greedy quantifier flag

	// Char class
	cc_index        int    = -1

	// counters for quantifier check (repetitions)
	rep             int    = 0

	// validator function pointer
	validator FnValidator

	// groups variables
	group_rep          int = 0     // repetition of the group
	group_id           int = -1    // id of the group
	goto_pc            int = -1    // jump to this PC if is needed

	// OR flag for the token
	next_is_or bool        = false // true if the next token is an OR
}

[inline]
fn (mut tok Token) reset() {
	tok.rep = 0
}

/*

Regex struct

*/
pub const (
	f_nl  = 0x00000001  // end the match when find a new line symbol
	f_ms  = 0x00000002  // match true only if the match is at the start of the string
	f_me  = 0x00000004  // match true only if the match is at the end of the string

	f_efm = 0x00000100  // exit on first token matched, used by search
	f_bin = 0x00000200  // work only on bytes, ignore utf-8

	// behaviour modifier flags
	//f_or  = 0x00010000  // the OR work with concatenation like PCRE
	f_src = 0x00020000  // search mode enabled
)

struct StateDotObj{
mut:
	i  int                = -1  // char index in the input buffer
	pc int                = -1  // program counter saved
	mi int                = -1  // match_index saved
	group_stack_index int = -1  // continuous save on capturing groups
}

pub type FnLog fn (string)

pub
struct RE {
pub mut:
	prog []Token

	// char classes storage
	cc []CharClass             // char class list
	cc_index int         = 0   // index

	// state index
	state_stack_index int= -1
	state_stack []StateDotObj


	// groups
	group_count int      = 0   // number of groups in this regex struct
	groups []int               // groups index results
	group_max_nested int = 3   // max nested group
	group_max int        = 8   // max allowed number of different groups

	group_csave []int    = []int{}  // groups continuous save array
	group_csave_index int= -1       // groups continuous save index

	group_map map[string]int   // groups names map

	// flags
	flag int             = 0   // flag for optional parameters

	// Debug/log
	debug int            = 0           // enable in order to have the unroll of the code 0 = NO_DEBUG, 1 = LIGHT 2 = VERBOSE
	log_func FnLog       = simple_log  // log function, can be customized by the user
	query string         = ""          // query string
}

// Reset RE object
//[inline]
fn (mut re RE) reset(){
	re.cc_index         = 0

	mut i := 0
	for i < re.prog.len {
		re.prog[i].group_rep          = 0 // clear repetition of the group
		re.prog[i].rep                = 0 // clear repetition of the token
		i++
	}
	re.groups = [-1].repeat(re.group_count*2)

	re.state_stack_index = -1

	// reset group_csave
	if re.group_csave.len > 0 {
		re.group_csave_index = 1
		re.group_csave[0] = 0     // reset the capture count
	}
}

// reset for search mode fail
// gcc bug, dont use [inline] or go 5 time slower
fn (mut re RE) reset_src(){
	mut i := 0
	for i < re.prog.len {
		re.prog[i].group_rep          = 0 // clear repetition of the group
		re.prog[i].rep                = 0 // clear repetition of the token
		i++
	}
	re.state_stack_index = -1
}

// get_group get a group boundaries by its name
pub fn (re RE) get_group(group_name string) (int, int) {
	if group_name in re.group_map {
		tmp_index := re.group_map[group_name]-1
		start := re.groups[tmp_index*2]
		end := re.groups[tmp_index*2+1]
		return start,end
	}
	return -1, -1
}

/*

Backslashes chars

*/
struct BslsStruct {
	ch u32                   // meta char
	validator FnValidator    // validator function pointer
}

const(
	bsls_validator_array = [
		BslsStruct{`w`, is_alnum},
		BslsStruct{`W`, is_not_alnum},
		BslsStruct{`s`, is_space},
		BslsStruct{`S`, is_not_space},
		BslsStruct{`d`, is_digit},
		BslsStruct{`D`, is_not_digit},
		BslsStruct{`a`, is_lower},
		BslsStruct{`A`, is_upper},
	]

	// these chars are escape if preceded by a \
	bsls_escape_list = [ `\\`,`|`,`.`,`*`,`+`,`-`,`{`,`}`,`[`,`]` ]
)

enum BSLS_parse_state {
		start
		bsls_found
		bsls_char
		normal_char
}

// parse_bsls return (index, str_len) bsls_validator_array index, len of the backslash sequence if present
fn (re RE) parse_bsls(in_txt string, in_i int) (int,int){
	mut status := BSLS_parse_state.start
	mut i := in_i

	for i < in_txt.len {
		// get our char
		char_tmp,char_len := re.get_char(in_txt,i)
		ch := byte(char_tmp)

		if status == .start && ch == `\\` {
			status = .bsls_found
			i += char_len
			continue
		}

		// check if is our bsls char, for now only one length sequence
		if status == .bsls_found {
			for c,x in bsls_validator_array {
				if x.ch == ch {
					return c,i-in_i+1
				}
			}
			status = .normal_char
			continue
		}

		// no BSLS validator, manage as normal escape char char
		if status == .normal_char {
			if ch in bsls_escape_list {
				return no_match_found,i-in_i+1
			}
			return err_syntax_error,i-in_i+1
		}

		// at the present time we manage only one char after the \
		break

	}
	// not our bsls return KO
	return err_syntax_error, i
}

/*

Char class

*/
const(
	cc_null = 0    // empty cc token
	cc_char = 1    // simple char: a
	cc_int  = 2    // char interval: a-z
	cc_bsls = 3    // backslash char
	cc_end  = 4    // cc sequence terminator
)

struct CharClass {
mut:
	cc_type int = cc_null      // type of cc token
	ch0 u32     = u32(0)       // first char of the interval a-b  a in this case
	ch1 u32     = u32(0)	   // second char of the interval a-b b in this case
	validator FnValidator      // validator function pointer
}

enum CharClass_parse_state {
	start
	in_char
	in_bsls
	separator
	finish
}

fn (re RE) get_char_class(pc int) string {
	buf := [byte(0)].repeat(re.cc.len)
	mut buf_ptr := &byte(&buf)

	mut cc_i := re.prog[pc].cc_index
	mut i := 0
	mut tmp := 0
	for cc_i >= 0 && cc_i < re.cc.len && re.cc[cc_i].cc_type != cc_end {

		if re.cc[cc_i].cc_type == cc_bsls {
			buf_ptr[i++] = `\\`
			buf_ptr[i++] = byte(re.cc[cc_i].ch0)
		}
		else if re.cc[cc_i].ch0 == re.cc[cc_i].ch1 {
			tmp = 3
			for tmp >= 0 {
				x := byte((re.cc[cc_i].ch0 >> (tmp*8)) & 0xFF)
				if x != 0 {
					buf_ptr[i++] = x
				}
				tmp--
			}
		}
		else {
			tmp = 3
			for tmp >= 0 {
				x := byte((re.cc[cc_i].ch0 >> (tmp*8)) & 0xFF)
				if x != 0 {
					buf_ptr[i++] = x
				}
				tmp--
			}
			buf_ptr[i++] = `-`
			tmp = 3
			for tmp >= 0 {
				x := byte((re.cc[cc_i].ch1 >> (tmp*8)) & 0xFF)
				if x != 0 {
					buf_ptr[i++] = x
				}
				tmp--
			}
		}
		cc_i++
	}
	buf_ptr[i] = byte(0)

	return tos_clone( buf_ptr )
}

fn (re RE) check_char_class(pc int, ch u32) bool {
	mut cc_i := re.prog[pc].cc_index
	for cc_i >= 0 && cc_i < re.cc.len && re.cc[cc_i].cc_type != cc_end {
		if re.cc[cc_i].cc_type == cc_bsls {
			if re.cc[cc_i].validator(byte(ch)) {
				return true
			}
		}
		else if ch >= re.cc[cc_i].ch0 && ch <= re.cc[cc_i].ch1 {
			return true
		}
		cc_i++
	}
	return false
}

// parse_char_class return (index, str_len, cc_type) of a char class [abcm-p], char class start after the [ char
fn (mut re RE) parse_char_class(in_txt string, in_i int) (int, int, u32) {
	mut status := CharClass_parse_state.start
	mut i := in_i

	mut tmp_index := re.cc_index
	res_index := re.cc_index

	mut cc_type := u32(ist_char_class_pos)

	for i < in_txt.len {

		// check if we are out of memory for char classes
		if tmp_index >= re.cc.len {
			return err_cc_alloc_overflow,0,u32(0)
		}

		// get our char
		char_tmp,char_len := re.get_char(in_txt,i)
		ch := byte(char_tmp)

		//println("CC #${i:3d} ch: ${ch:c}")

		// negation
		if status == .start && ch == `^` {
			cc_type = u32(ist_char_class_neg)
			i += char_len
			continue
		}

		// minus symbol
		if status == .start && ch == `-` {
			re.cc[tmp_index].cc_type = cc_char
			re.cc[tmp_index].ch0     = char_tmp
			re.cc[tmp_index].ch1     = char_tmp
			i += char_len
			tmp_index++
			continue
		}

		// bsls
		if (status == .start || status == .in_char) && ch == `\\` {
			//println("CC bsls.")
			status = .in_bsls
			i += char_len
			continue
		}

		if status == .in_bsls {
			//println("CC bsls validation.")
			for c,x in bsls_validator_array {
				if x.ch == ch {
					//println("CC bsls found [${ch:c}]")
					re.cc[tmp_index].cc_type   = cc_bsls
					re.cc[tmp_index].ch0       = bsls_validator_array[c].ch
					re.cc[tmp_index].ch1       = bsls_validator_array[c].ch
					re.cc[tmp_index].validator = bsls_validator_array[c].validator
					i += char_len
					tmp_index++
					status = .in_char
					break
				}
			}
			if status == .in_bsls {
				println("CC bsls not found [${ch:c}]")
				status = .in_char
			}else {
				continue
			}
		}

		// simple char
		if (status == .start || status == .in_char) &&
			ch != `-` && ch != `]`
		{
			status = .in_char

			re.cc[tmp_index].cc_type = cc_char
			re.cc[tmp_index].ch0     = char_tmp
			re.cc[tmp_index].ch1     = char_tmp

			i += char_len
			tmp_index++
			continue
		}

		// check range separator
		if status == .in_char && ch == `-` {
			status = .separator
			i += char_len
			continue
		}

		// check range end
		if status == .separator && ch != `]` && ch != `-` {
			status = .in_char
			re.cc[tmp_index-1].cc_type = cc_int
			re.cc[tmp_index-1].ch1     = char_tmp
			i += char_len
			continue
		}

		// char class end
		if status == .in_char && ch == `]` {
			re.cc[tmp_index].cc_type = cc_end
			re.cc[tmp_index].ch0     = 0
			re.cc[tmp_index].ch1     = 0
			re.cc_index = tmp_index+1

			return res_index, i-in_i+2, cc_type
		}

		i++
	}
	return err_syntax_error,0,u32(0)
}

/*

Re Compiler

*/
//
// Quantifier
//
enum Quant_parse_state {
	start
	min_parse
	comma_checked
	max_parse
	greedy
	gredy_parse
	finish
}

// parse_quantifier return (min, max, str_len, greedy_flag) of a {min,max}? quantifier starting after the { char
fn (re RE) parse_quantifier(in_txt string, in_i int) (int, int, int, bool) {
	mut status := Quant_parse_state.start
	mut i := in_i

	mut q_min := 0 // default min in a {} quantifier is 1
	mut q_max := 0 // deafult max in a {} quantifier is max_quantifier

	mut ch := byte(0)

	for i < in_txt.len {
		ch = in_txt.str[i]

		//println("${ch:c} status: $status")

		// exit on no compatible char with {} quantifier
		if utf8util_char_len(ch) != 1 {
			return err_syntax_error,i,0,false
		}

		// min parsing skip if comma present
		if status == .start && ch == `,` {
			q_min = 0 // default min in a {} quantifier is 0
			status = .comma_checked
			i++
			continue
		}

		if status == .start && is_digit( ch ) {
			status = .min_parse
			q_min *= 10
			q_min += int(ch - `0`)
			i++
			continue
		}

		if status == .min_parse && is_digit( ch ) {
			q_min *= 10
			q_min += int(ch - `0`)
			i++
			continue
		}

		// we have parsed the min, now check the max
		if status == .min_parse && ch == `,` {
			status = .comma_checked
			i++
			continue
		}

		// single value {4}
		if status == .min_parse && ch == `}` {
			q_max = q_min

			status = .greedy
			continue
		}

		// end without max
		if status == .comma_checked && ch == `}` {
			q_max = max_quantifier

			status = .greedy
			continue
		}

		// start max parsing
		if status == .comma_checked && is_digit( ch ) {
			status = .max_parse
			q_max *= 10
			q_max += int(ch - `0`)
			i++
			continue
		}

		// parse the max
		if status == .max_parse && is_digit( ch ) {
			q_max *= 10
			q_max += int(ch - `0`)
			i++
			continue
		}

		// finished the quantifier
		if status == .max_parse && ch == `}` {
			status = .greedy
			continue
		}

		// check if greedy flag char ? is present
		if status == .greedy {
			if i+1 < in_txt.len {
				i++
				status = .gredy_parse
				continue
			}
			return q_min, q_max, i-in_i+2, false
		}

		// check the greedy flag
		if status == .gredy_parse {
			if ch == `?` {
				return q_min, q_max, i-in_i+2, true
			} else {
				i--
				return q_min, q_max, i-in_i+2, false
			}
		}

		// not  a {} quantifier, exit
		return err_syntax_error, i, 0, false
	}

	// not a conform {} quantifier
	return err_syntax_error, i, 0, false
}

//
// Groups
//
enum Group_parse_state {
	start
	q_mark      // (?
	q_mark1     // (?:|P  checking
	p_status    // (?P
	p_start     // (?P<
	p_end       // (?P<...>
	p_in_name   // (?P<...
	finish
}

// parse_groups parse a group for ? (question mark) syntax, if found, return (error, capture_flag, name_of_the_group, next_index)
fn (re RE) parse_groups(in_txt string, in_i int) (int, bool, string, int) {
	mut status := Group_parse_state.start
	mut i := in_i
	mut name := ''

	for i < in_txt.len && status != .finish {

		// get our char
		char_tmp,char_len := re.get_char(in_txt,i)
		ch := byte(char_tmp)

		// start
		if status == .start && ch == `(` {
			status = .q_mark
			i += char_len
			continue
		}

		// check for question marks
		if status == .q_mark && ch == `?` {
			status = .q_mark1
			i += char_len
			continue
		}

		// non capturing group
		if status == .q_mark1 && ch == `:` {
			i += char_len
			return 0, false, name, i
		}

		// enter in P section
		if status == .q_mark1 && ch == `P` {
			status = .p_status
			i += char_len
			continue
		}

		// not a valid q mark found
		if status == .q_mark1 {
			//println("NO VALID Q MARK")
			return -2 , true, name, i
		}

		if status == .p_status && ch == `<` {
			status = .p_start
			i += char_len
			continue
		}

		if status == .p_start && ch != `>` {
			status = .p_in_name
			name += "${ch:1c}" // TODO: manage utf8 chars
			i += char_len
			continue
		}

		// colect name
		if status == .p_in_name && ch != `>` && is_alnum(ch) {
			name += "${ch:1c}" // TODO: manage utf8 chars
			i += char_len
			continue
		}

		// end name
		if status == .p_in_name && ch == `>` {
			i += char_len
			return 0, true, name, i
		}

		// error on name group
		if status == .p_in_name {
			return -2 , true, name, i
		}

		// normal group, nothig to do, exit
		return  0 , true, name, i
	}
	/* UNREACHABLE */
	//println("ERROR!! NOT MEANT TO BE HERE!!1")
	return -2 , true, name, i
}

//
// main compiler
//
// compile return (return code, index) where index is the index of the error in the query string if return code is an error code
pub fn (mut re RE) compile(in_txt string) (int,int) {
	mut i        := 0      // input string index
	mut pc       := 0      // program counter
	mut tmp_code := u32(0)

	// group management variables
	mut group_count           := -1
	mut group_stack           := [0 ].repeat(re.group_max_nested)
	mut group_stack_txt_index := [-1].repeat(re.group_max_nested)
	mut group_stack_index     := -1

	re.query = in_txt      // save the query string

	i = 0
	for i < in_txt.len {
		tmp_code = u32(0)
		mut char_tmp := u32(0)
		mut char_len := 0
		//println("i: ${i:3d} ch: ${in_txt.str[i]:c}")

		char_tmp,char_len = re.get_char(in_txt,i)

		//
		// check special cases: $ ^
		//
		if char_len == 1 && i == 0 && byte(char_tmp) == `^` {
			re.flag = f_ms
			i = i + char_len
			continue
		}
		if char_len == 1 && i == (in_txt.len-1) && byte(char_tmp) == `$` {
			re.flag = f_me
			i = i + char_len
			continue
		}

		// ist_group_start
		if char_len == 1 && pc >= 0 && byte(char_tmp) == `(` {

			//check max groups allowed
			if group_count > re.group_max {
				return err_groups_overflow,i+1
			}
			group_stack_index++

			// check max nested groups allowed
			if group_stack_index > re.group_max_nested {
				return err_groups_max_nested,i+1
			}

			tmp_res, cgroup_flag, cgroup_name, next_i := re.parse_groups(in_txt,i)

			// manage question mark format error
			if tmp_res < -1 {
				return err_group_qm_notation,next_i
			}

			//println("Parse group: [$tmp_res, $cgroup_flag, ($i,$next_i), '${in_txt[i..next_i]}' ]")
			i = next_i

			if cgroup_flag == true {
				group_count++
			}

			// calculate the group id
			// if it is a named group, recycle the group id
			// NOTE: **** the group index is +1 because map return 0 when not found!! ****
			mut group_id := group_count
			if cgroup_name.len > 0 {
				//println("GROUP NAME: ${cgroup_name}")
				if cgroup_name in re.group_map{
					group_id = re.group_map[cgroup_name]-1
					group_count--
				} else {
					re.group_map[cgroup_name] = group_id+1
				}
			}

			group_stack_txt_index[group_stack_index] = i
			group_stack[group_stack_index] = pc

			re.prog[pc].ist = u32(0) | ist_group_start
			re.prog[pc].rep_min = 1
			re.prog[pc].rep_max = 1

			// set the group id
			if cgroup_flag == false {
				//println("NO CAPTURE GROUP")
				re.prog[pc].group_id = -1
			} else {
				re.prog[pc].group_id = group_id
			}

			pc = pc + 1
			continue

		}

		// ist_group_end
		if char_len==1 && pc > 0 && byte(char_tmp) == `)` {
			if group_stack_index < 0 {
				return err_group_not_balanced,i+1
			}

			goto_pc := group_stack[group_stack_index]
			group_stack_index--

			re.prog[pc].ist = u32(0) | ist_group_end
			re.prog[pc].rep_min = 1
			re.prog[pc].rep_max = 1

			re.prog[pc].goto_pc = goto_pc			          // PC where to jump if a group need
			re.prog[pc].group_id = re.prog[goto_pc].group_id  // id of this group, used for storing data

			re.prog[goto_pc].goto_pc = pc                     // start goto point to the end group pc
			//re.prog[goto_pc].group_id = group_count         // id of this group, used for storing data

			pc = pc + 1
			i = i + char_len
			continue
		}

		// ist_dot_char match any char except the following token
		if char_len==1 && pc >= 0 && byte(char_tmp) == `.` {
			re.prog[pc].ist = u32(0) | ist_dot_char
			re.prog[pc].rep_min = 1
			re.prog[pc].rep_max = 1
			pc = pc + 1
			i = i + char_len
			continue
		}

		// OR branch
		if char_len==1 && pc > 0 && byte(char_tmp) == `|` {
			// two consecutive ist_dot_char are an error
			if pc > 0 && re.prog[pc-1].ist == ist_or_branch {
				return err_syntax_error,i
			}
			re.prog[pc].ist = u32(0) | ist_or_branch
			pc = pc + 1
			i = i + char_len
			continue
		}

		// Quantifiers
		if char_len==1 && pc > 0{
			mut quant_flag := true
			match byte(char_tmp) {
				`?` {
					//println("q: ${char_tmp:c}")
					re.prog[pc-1].rep_min = 0
					re.prog[pc-1].rep_max = 1
				}

				`+` {
					//println("q: ${char_tmp:c}")
					re.prog[pc-1].rep_min = 1
					re.prog[pc-1].rep_max = max_quantifier
				}

				`*` {
					//println("q: ${char_tmp:c}")
					re.prog[pc-1].rep_min = 0
					re.prog[pc-1].rep_max = max_quantifier
				}

				`{` {
					min, max, tmp, greedy := re.parse_quantifier(in_txt, i+1)
					// it is a quantifier
					if min >= 0 {
						//println("{$min,$max}\n str:[${in_txt[i..i+tmp]}] greedy:$greedy")
						i = i + tmp
						re.prog[pc-1].rep_min = min
						re.prog[pc-1].rep_max = max
						re.prog[pc-1].greedy  = greedy
						continue
					}
					else {
						return min,i
					}
					// TODO: decide if the open bracket can be conform without the close bracket
					/*
					// no conform, parse as normal char
					else {
						quant_flag = false
					}
					*/
				}
				else{
					quant_flag = false
				}
			}

			if quant_flag {
				i = i + char_len
				continue
			}
		}

		// IST_CHAR_CLASS_*
		if char_len==1 && pc >= 0{
			if byte(char_tmp) == `[` {
				cc_index,tmp,cc_type := re.parse_char_class(in_txt, i+1)
				if cc_index >= 0 {
					//println("index: $cc_index str:${in_txt[i..i+tmp]}")
					i = i + tmp
					re.prog[pc].ist      = u32(0) | cc_type
					re.prog[pc].cc_index = cc_index
					re.prog[pc].rep_min  = 1
					re.prog[pc].rep_max  = 1
					pc = pc + 1
					continue
				}

				// cc_class vector memory full
				else if cc_index < 0 {
					return cc_index, i
				}
			}
		}

		// ist_bsls_char
		if char_len==1 && pc >= 0{
			if byte(char_tmp) == `\\` {
				bsls_index,tmp := re.parse_bsls(in_txt,i)
				//println("index: $bsls_index str:${in_txt[i..i+tmp]}")
				if bsls_index >= 0 {
					i = i + tmp
					re.prog[pc].ist       = u32(0) | ist_bsls_char
					re.prog[pc].rep_min   = 1
					re.prog[pc].rep_max   = 1
					re.prog[pc].validator = bsls_validator_array[bsls_index].validator
					re.prog[pc].ch      = bsls_validator_array[bsls_index].ch
					pc = pc + 1
					continue
				}
				// this is an escape char, skip the bsls and continue as a normal char
				else if bsls_index == no_match_found {
					i += char_len
					char_tmp,char_len = re.get_char(in_txt,i)
					// continue as simple char
				}
				// if not an escape or a bsls char then it is an error (at least for now!)
				else {
					return bsls_index,i+tmp
				}
			}
		}

		// ist_simple_char
		re.prog[pc].ist     = ist_simple_char
		re.prog[pc].ch      = char_tmp
		re.prog[pc].ch_len  = byte(char_len)
		re.prog[pc].rep_min = 1
		re.prog[pc].rep_max = 1
		//println("char: ${char_tmp:c}")
		pc = pc +1

		i+=char_len
	}

	// add end of the program
	re.prog[pc].ist = ist_prog_end

	// check for unbalanced groups
	if group_stack_index != -1 {
		return err_group_not_balanced, group_stack_txt_index[group_stack_index]+1
	}

	// check for OR at the end of the program
	if pc > 0 && re.prog[pc-1].ist == ist_or_branch {
		return err_syntax_error,in_txt.len
	}

	// store the number of groups in the query
	re.group_count = group_count+1

	//******************************************
	// Post processing
	//******************************************

	// count ist_dot_char to set the size of the state stack
	mut pc1 := 0
	mut tmp_count := 0
	for pc1 < pc {
		if re.prog[pc1].ist == ist_dot_char {
			tmp_count++
		}
		pc1++
	}

	// init the state stack
	re.state_stack = [StateDotObj{}].repeat(tmp_count+1)

	// OR branch
	// a|b|cd
	// d exit point
	// a,b,c branches
	// set the jump in the right places
	pc1 = 0
	for pc1 < pc-2 {
		// two consecutive OR are a syntax error
		if re.prog[pc1+1].ist == ist_or_branch && re.prog[pc1+2].ist == ist_or_branch {
			return err_syntax_error, i
		}

		// manange a|b chains like a|(b)|c|d...
		// standard solution
		if re.prog[pc1].ist != ist_or_branch &&
			re.prog[pc1+1].ist == ist_or_branch &&
			re.prog[pc1+2].ist != ist_or_branch
		{
			re.prog[pc1].next_is_or = true   // set that the next token is an  OR
			re.prog[pc1+1].rep_min = pc1+2   // failed match jump

			// match jump, if an OR chain the next token will be an OR token
			mut pc2 := pc1+2
			for pc2 < pc-1 {
				ist := re.prog[pc2].ist
				if  ist == ist_group_start {
					re.prog[pc1+1].rep_max = re.prog[pc2].goto_pc + 1
					break
				}
				if ist != ist_or_branch {
					re.prog[pc1+1].rep_max = pc2 + 1
					break
				}
				pc2++
			}
			//println("Compile OR postproc. [$pc1,OR ${pc1+1},$pc2]")
			pc1 = pc2
			continue
		}

		pc1++
	}

	//******************************************
	// DEBUG PRINT REGEX GENERATED CODE
	//******************************************
	if re.debug > 0 {
		gc := re.get_code()
		re.log_func( gc )
	}
	//******************************************

	return compile_ok, 0
}

// get_code return the compiled code as regex string, note: may be different from the source!
pub fn (re RE) get_code() string {
		mut pc1 := 0
		mut res := strings.new_builder(re.cc.len*2*re.prog.len)
		res.write("========================================\nv RegEx compiler v $v_regex_version output:\n")

		mut stop_flag := false

		for pc1 <= re.prog.len {
			tk := re.prog[pc1]
			res.write("PC:${pc1:3d}")

		    res.write(" ist: ")
		    res.write("${tk.ist:8x}".replace(" ","0") )
		    res.write(" ")
			ist :=tk.ist
			if ist == ist_bsls_char {
				res.write("[\\${tk.ch:1c}]     BSLS")
			} else if ist == ist_prog_end {
				res.write("PROG_END")
				stop_flag = true
			} else if ist == ist_or_branch {
				res.write("OR      ")
			} else if ist == ist_char_class_pos {
				res.write("[${re.get_char_class(pc1)}]     CHAR_CLASS_POS")
			} else if ist == ist_char_class_neg {
				res.write("[^${re.get_char_class(pc1)}]    CHAR_CLASS_NEG")
			} else if ist == ist_dot_char {
				res.write(".        DOT_CHAR")
			} else if ist == ist_group_start {
				res.write("(        GROUP_START #:${tk.group_id}")
				if tk.group_id == -1 {
					res.write(" ?:")
				} else {
					for x in re.group_map.keys() {
						if re.group_map[x] == (tk.group_id+1) {
							res.write(" ?P<${x}>")
							break
						}
					}
				}
			} else if ist == ist_group_end {
				res.write(")        GROUP_END   #:${tk.group_id}")
			} else if ist == ist_simple_char {
				res.write("[${tk.ch:1c}]      query_ch")
			}

			if tk.rep_max == max_quantifier {
				res.write(" {${tk.rep_min:3d},MAX}")
			}else{
				if ist == ist_or_branch {
					res.write(" if false go: ${tk.rep_min:3d} if true go: ${tk.rep_max:3d}")
				} else {
					res.write(" {${tk.rep_min:3d},${tk.rep_max:3d}}")
				}
				if tk.greedy == true {
					res.write("?")
				}
			}
			res.write("\n")
			if stop_flag {
				break
			}
			pc1++
		}

		res.write("========================================\n")
		return res.str()
}

// get_query return a string with a reconstruction of the query starting from the regex program code
pub fn (re RE) get_query() string {
	mut res := strings.new_builder(re.query.len*2)

	if (re.flag & f_ms) != 0 {
		res.write("^")
	}

	mut i := 0
	for i < re.prog.len && re.prog[i].ist != ist_prog_end && re.prog[i].ist != 0{
		tk := &re.prog[i]
		ch := tk.ist

		// GROUP start
		if ch == ist_group_start {
			if re.debug == 0 {
				res.write("(")
			} else {
				if tk.group_id == -1 {
					res.write("(?:")   // non capturing group
				} else {
					res.write("#${tk.group_id}(")
				}
			}

			for x in re.group_map.keys() {
				if re.group_map[x] == (tk.group_id+1) {
					res.write("?P<${x}>")
					break
				}
			}

			i++
			continue
		}

		// GROUP end
		if ch == ist_group_end {
			res.write(")")
		}

		// OR branch
		if ch == ist_or_branch {
			res.write("|")
			if re.debug > 0 {
				res.write("{${tk.rep_min},${tk.rep_max}}")
			}
			i++
			continue
		}

		// char class
		if ch == ist_char_class_neg || ch == ist_char_class_pos {
			res.write("[")
			if ch == ist_char_class_neg {
				res.write("^")
			}
			res.write("${re.get_char_class(i)}")
			res.write("]")
		}

		// bsls char
		if ch == ist_bsls_char {
			res.write("\\${tk.ch:1c}")
		}

		// ist_dot_char
		if ch == ist_dot_char {
			res.write(".")
		}

		// char alone
		if ch == ist_simple_char {
			if byte(ch) in bsls_escape_list {
				res.write("\\")
			}
			res.write("${tk.ch:c}")
		}

		// quantifier
		if !(tk.rep_min == 1 && tk.rep_max == 1) {
			if tk.rep_min == 0 && tk.rep_max == 1 {
				res.write("?")
			} else if tk.rep_min == 1 && tk.rep_max == max_quantifier {
				res.write("+")
			} else if tk.rep_min == 0 && tk.rep_max == max_quantifier {
				res.write("*")
			} else {
				if tk.rep_max == max_quantifier {
					res.write("{${tk.rep_min},MAX}")
				} else {
					res.write("{${tk.rep_min},${tk.rep_max}}")
				}
				if tk.greedy == true {
					res.write("?")
				}
			}
		}
		i++
	}
	if (re.flag & f_me) != 0 {
		res.write("$")
	}

	return res.str()
}

/*

Matching

*/
enum Match_state{
	start = 0
	stop
	end
	new_line

	ist_load     // load and execute instruction
	ist_next     // go to next instruction
	ist_next_ks  // go to next instruction without clenaning the state
	ist_quant_p  // match positive ,quantifier check
	ist_quant_n  // match negative, quantifier check
	ist_quant_pg // match positive ,group quantifier check
	ist_quant_ng // match negative ,group quantifier check
}

fn state_str(s Match_state) string {
	match s{
		.start        { return "start" }
		.stop         { return "stop" }
		.end          { return "end" }
		.new_line     { return "new line" }

		.ist_load     { return "ist_load" }
		.ist_next     { return "ist_next" }
		.ist_next_ks  { return "ist_next_ks" }
		.ist_quant_p  { return "ist_quant_p" }
		.ist_quant_n  { return "ist_quant_n" }
		.ist_quant_pg { return "ist_quant_pg" }
		.ist_quant_ng { return "ist_quant_ng" }
	}
}

struct StateObj {
pub mut:
	match_flag bool = false
	match_index int = -1
	match_first int = -1
}

pub fn (mut re RE) match_base(in_txt byteptr, in_txt_len int ) (int,int) {
	// result status
	mut result := no_match_found     // function return
	mut first_match := -1             //index of the first match

	mut i := 0                       // source string index
	mut ch := u32(0)                 // examinated char
	mut char_len := 0                // utf8 examinated char len
	mut m_state := Match_state.start // start point for the matcher FSM

	mut pc := -1                     // program counter
	mut state := StateObj{}          // actual state
	mut ist := u32(0)                // actual instruction
	mut l_ist := u32(0)              // last matched instruction

	mut group_stack      := [-1].repeat(re.group_max)
	mut group_data       := [-1].repeat(re.group_max)

	mut group_index := -1            // group id used to know how many groups are open

	mut step_count := 0              // stats for debug
	mut dbg_line   := 0              // count debug line printed

	re.reset()

	if re.debug>0 {
		// print header
		mut h_buf := strings.new_builder(32)
		h_buf.write("flags: ")
		h_buf.write("${re.flag:8x}".replace(" ","0"))
		h_buf.write("\n")
		sss := h_buf.str()
		re.log_func(sss)
	}

	for m_state != .end {

		if pc >= 0 && pc < re.prog.len {
			ist = re.prog[pc].ist
		}else if pc >= re.prog.len {
			//println("ERROR!! PC overflow!!")
			return err_internal_error, i
		}

		//******************************************
		// DEBUG LOG
		//******************************************
		if re.debug>0 {
			mut buf2 := strings.new_builder(re.cc.len+128)

			// print all the instructions

			// end of the input text
			if i >= in_txt_len {
				buf2.write("# ${step_count:3d} END OF INPUT TEXT\n")
				sss := buf2.str()
				re.log_func(sss)
			}else{

				// print only the exe instruction
				if (re.debug == 1 && m_state == .ist_load) ||
					re.debug == 2
				{
					if ist == ist_prog_end {
						buf2.write("# ${step_count:3d} PROG_END\n")
					}
					else if ist == 0 || m_state in [.start,.ist_next,.stop] {
						buf2.write("# ${step_count:3d} s: ${state_str(m_state):12s} PC: NA\n")
					}else{
						ch, char_len = re.get_charb(in_txt,i)

						buf2.write("# ${step_count:3d} s: ${state_str(m_state):12s} PC: ${pc:3d}=>")
						buf2.write("${ist:8x}".replace(" ","0"))
						buf2.write(" i,ch,len:[${i:3d},'${utf8_str(ch)}',${char_len}] f.m:[${first_match:3d},${state.match_index:3d}] ")

						if ist == ist_simple_char {
							buf2.write("query_ch: [${re.prog[pc].ch:1c}]")
						} else {
							if ist == ist_bsls_char {
								buf2.write("BSLS [\\${re.prog[pc].ch:1c}]")
							} else if ist == ist_prog_end {
								buf2.write("PROG_END")
							} else if ist == ist_or_branch {
								buf2.write("OR")
							} else if ist == ist_char_class_pos {
								buf2.write("CHAR_CLASS_POS[${re.get_char_class(pc)}]")
							} else if ist == ist_char_class_neg {
								buf2.write("CHAR_CLASS_NEG[${re.get_char_class(pc)}]")
							} else if ist == ist_dot_char {
								buf2.write("DOT_CHAR")
							} else if ist == ist_group_start {
								tmp_gi :=re.prog[pc].group_id
								tmp_gr := re.prog[re.prog[pc].goto_pc].group_rep
								buf2.write("GROUP_START #:${tmp_gi} rep:${tmp_gr} ")
							} else if ist == ist_group_end {
								buf2.write("GROUP_END   #:${re.prog[pc].group_id} deep:${group_index}")
							}
						}
						if re.prog[pc].rep_max == max_quantifier {
							buf2.write("{${re.prog[pc].rep_min},MAX}:${re.prog[pc].rep}")
						} else {
							buf2.write("{${re.prog[pc].rep_min},${re.prog[pc].rep_max}}:${re.prog[pc].rep}")
						}
						if re.prog[pc].greedy == true {
							buf2.write("?")
						}
						buf2.write(" (#${group_index})\n")
					}
					sss2 := buf2.str()
					re.log_func( sss2 )
				}
			}
			step_count++
			dbg_line++
		}
		//******************************************

		// we're out of text, manage it
		if i >= in_txt_len || m_state == .new_line {

			// manage groups
			if group_index >= 0 && state.match_index >= 0 {
				//println("End text with open groups!")
				// close the groups
				for group_index >= 0 {
					tmp_pc := group_data[group_index]
					re.prog[tmp_pc].group_rep++
					//println("Closing group $group_index {${re.prog[tmp_pc].rep_min},${re.prog[tmp_pc].rep_max}}:${re.prog[tmp_pc].group_rep}")

					if re.prog[tmp_pc].group_rep >= re.prog[tmp_pc].rep_min && re.prog[tmp_pc].group_id >= 0{
						start_i   := group_stack[group_index]
	 					group_stack[group_index]=-1

	 					// save group results
						g_index := re.prog[tmp_pc].group_id*2
						if start_i >= 0 {
							re.groups[g_index] = start_i
						} else {
							re.groups[g_index] = 0
						}
						re.groups[g_index+1] = i

						// continuous save, save until we have space
						if re.group_csave_index > 0 {
							// check if we have space to save the record
							if (re.group_csave_index + 3) < re.group_csave.len {
								// incrment counter
								re.group_csave[0]++
								// save the record
								re.group_csave[re.group_csave_index++] = g_index >> 1          // group id
								re.group_csave[re.group_csave_index++] = re.groups[g_index]    // start
								re.group_csave[re.group_csave_index++] = re.groups[g_index+1]  // end
							}
						}

 					}

					group_index--
				}
			}

			// manage ist_dot_char

			m_state == .end
			break
			//return no_match_found,0
		}

		// starting and init
		if m_state == .start {
			pc = -1
			i = 0
			m_state = .ist_next
			continue
		}

		// ist_next, next instruction reseting its state
		if m_state == .ist_next {
			pc = pc + 1
			re.prog[pc].reset()
			// check if we are in the program bounds
			if pc < 0 || pc > re.prog.len {
				//println("ERROR!! PC overflow!!")
				return err_internal_error, i
			}
			m_state = .ist_load
			continue
		}

		// ist_next_ks, next instruction keeping its state
		if m_state == .ist_next_ks {
			pc = pc + 1
			// check if we are in the program bounds
			if pc < 0 || pc > re.prog.len {
				//println("ERROR!! PC overflow!!")
				return err_internal_error, i
			}
			m_state = .ist_load
			continue
		}

		// load the char
		ch, char_len = re.get_charb(in_txt,i)

		// check new line if flag f_nl enabled
		if (re.flag & f_nl) != 0 && char_len == 1 && byte(ch) in new_line_list {
			m_state = .new_line
			continue
		}

		// check if stop
		if m_state == .stop {

			// we are in search mode, don't exit until the end
			if re.flag & f_src != 0 && ist != ist_prog_end {
				pc = -1
				i += char_len
				m_state = .ist_next
				re.reset_src()
				state.match_index = -1
				first_match = -1
				continue
			}

			// if we are in restore state ,do it and restart
			//println("re.state_stack_index ${re.state_stack_index}")
			if re.state_stack_index >=0 && re.state_stack[re.state_stack_index].pc >= 0 {
				i = re.state_stack[re.state_stack_index].i
				pc = re.state_stack[re.state_stack_index].pc
				state.match_index =	re.state_stack[re.state_stack_index].mi
				group_index = re.state_stack[re.state_stack_index].group_stack_index

				m_state = .ist_load
				continue
			}

			if ist == ist_prog_end {
				return first_match,i
			}

			// exit on no match
			return result,0
		}

		// ist_load
		if m_state == .ist_load {

			// program end
			if ist == ist_prog_end {
				// if we are in match exit well

				if group_index >= 0 && state.match_index >= 0 {
					group_index = -1
				}

				// we have a DOT MATCH on going
				//println("ist_prog_end l_ist: ${l_ist:08x}", l_ist)
				if re.state_stack_index>=0 && l_ist == ist_dot_char {
					m_state = .stop
					continue
				}

				re.state_stack_index = -1
				m_state = .stop
				continue

			}

			// check GROUP start, no quantifier is checkd for this token!!
			else if ist == ist_group_start {
				group_index++
				group_data[group_index] = re.prog[pc].goto_pc  // save where is ist_group_end, we will use it for escape
				group_stack[group_index]=i                     // index where we start to manage
				//println("group_index $group_index rep ${re.prog[re.prog[pc].goto_pc].group_rep}")

				m_state = .ist_next
				continue
			}

			// check GROUP end
			else if ist == ist_group_end {
				// we are in matching streak
				if state.match_index >= 0 {
					// restore txt index stack and save the group data

					//println("g.id: ${re.prog[pc].group_id} group_index: ${group_index}")
					if group_index >= 0 && re.prog[pc].group_id >= 0 {
	 					start_i   := group_stack[group_index]
	 					//group_stack[group_index]=-1

	 					// save group results
						g_index := re.prog[pc].group_id*2
						if start_i >= 0 {
							re.groups[g_index] = start_i
						} else {
							re.groups[g_index] = 0
						}
						re.groups[g_index+1] = i
						//println("GROUP ${re.prog[pc].group_id} END [${re.groups[g_index]}, ${re.groups[g_index+1]}]")

						// continuous save, save until we have space
						if re.group_csave_index > 0 {
							// check if we have space to save the record
							if (re.group_csave_index + 3) < re.group_csave.len {
								// incrment counter
								re.group_csave[0]++
								// save the record
								re.group_csave[re.group_csave_index++] = g_index >> 1          // group id
								re.group_csave[re.group_csave_index++] = re.groups[g_index]    // start
								re.group_csave[re.group_csave_index++] = re.groups[g_index+1]  // end
							}
						}
					}

					re.prog[pc].group_rep++ // increase repetitions
					//println("GROUP $group_index END ${re.prog[pc].group_rep}")
					m_state = .ist_quant_pg
					continue

				}

				m_state = .ist_quant_ng
				continue
			}

			// check OR
			else if ist == ist_or_branch {
				if state.match_index >= 0 {
					pc = re.prog[pc].rep_max
					//println("ist_or_branch True pc: $pc")
				}else{
					pc = re.prog[pc].rep_min
					//println("ist_or_branch False pc: $pc")
				}
				re.prog[pc].reset()
				m_state == .ist_load
				continue
			}

			// check ist_dot_char
			else if ist == ist_dot_char {
				//println("ist_dot_char rep: ${re.prog[pc].rep}")
				state.match_flag = true
				l_ist = u32(ist_dot_char)

				if first_match < 0 {
					first_match = i
				}
				state.match_index = i
				re.prog[pc].rep++

				//if re.prog[pc].rep >= re.prog[pc].rep_min && re.prog[pc].rep <= re.prog[pc].rep_max {
				if re.prog[pc].rep >= 0 && re.prog[pc].rep <= re.prog[pc].rep_max {
					//println("DOT CHAR save state : ${re.state_stack_index}")
					// save the state

					// manage first dot char
					if re.state_stack_index < 0 {
						re.state_stack_index++
					}

					re.state_stack[re.state_stack_index].pc = pc
					re.state_stack[re.state_stack_index].mi = state.match_index
					re.state_stack[re.state_stack_index].group_stack_index = group_index
				} else {
					re.state_stack[re.state_stack_index].pc = -1
					re.state_stack[re.state_stack_index].mi = -1
					re.state_stack[re.state_stack_index].group_stack_index = -1
				}

				if re.prog[pc].rep >= 1 && re.state_stack_index >= 0 {
					re.state_stack[re.state_stack_index].i  = i + char_len
				}

				// manage * and {0,} quantifier
				if re.prog[pc].rep_min > 0 {
					i += char_len // next char
					l_ist = u32(ist_dot_char)
				}

				m_state = .ist_next
				continue

			}

			// char class IST
			else if ist == ist_char_class_pos || ist == ist_char_class_neg {
				state.match_flag = false
				mut cc_neg := false

				if ist == ist_char_class_neg {
					cc_neg = true
				}
				mut cc_res := re.check_char_class(pc,ch)

				if cc_neg {
					cc_res = !cc_res
				}

				if cc_res {
					state.match_flag = true
					l_ist = u32(ist_char_class_pos)

					if first_match < 0 {
						first_match = i
					}

					state.match_index = i

					re.prog[pc].rep++ // increase repetitions
					i += char_len // next char
					m_state = .ist_quant_p
					continue
				}
				m_state = .ist_quant_n
				continue
			}

			// check bsls
			else if ist == ist_bsls_char {
				state.match_flag = false
				tmp_res := re.prog[pc].validator(byte(ch))
				//println("BSLS in_ch: ${ch:c} res: $tmp_res")
				if tmp_res {
					state.match_flag = true
					l_ist = u32(ist_bsls_char)

					if first_match < 0 {
						first_match = i
					}

					state.match_index = i

					re.prog[pc].rep++ // increase repetitions
					i += char_len // next char
					m_state = .ist_quant_p
					continue
				}
				m_state = .ist_quant_n
				continue
			}

			// simple char IST
			else if ist == ist_simple_char {
				//println("ist_simple_char")
				state.match_flag = false

				if re.prog[pc].ch == ch
				{
					state.match_flag = true
					l_ist = ist_simple_char

					if first_match < 0 {
						first_match = i
					}
					//println("state.match_index: ${state.match_index}")
					state.match_index = i

					re.prog[pc].rep++ // increase repetitions
					i += char_len // next char
					m_state = .ist_quant_p
					continue
				}
				m_state = .ist_quant_n
				continue
			}
			/* UNREACHABLE */
			//println("PANIC2!! state: $m_state")
			return err_internal_error, i

		}

		/***********************************
		* Quantifier management
		***********************************/
		// ist_quant_ng
		if m_state == .ist_quant_ng {

			// we are finished here
			if group_index < 0 {
				//println("Early stop!")
				result = no_match_found
				m_state = .stop
				continue
			}

			tmp_pc := group_data[group_index]    // PC to the end of the group token
			rep    := re.prog[tmp_pc].group_rep  // use a temp variable
			re.prog[tmp_pc].group_rep = 0        // clear the repetitions

			//println(".ist_quant_ng group_pc_end: $tmp_pc rep: $rep")

			if rep >= re.prog[tmp_pc].rep_min {
				//println("ist_quant_ng GROUP CLOSED OK group_index: $group_index")

				i = group_stack[group_index]
				pc = tmp_pc
				group_index--
				m_state = .ist_next
				continue
			}
			else if re.prog[tmp_pc].next_is_or {
				//println("ist_quant_ng OR Negative branch")

				i = group_stack[group_index]
				pc = re.prog[tmp_pc+1].rep_min -1
				group_index--
				m_state = .ist_next
				continue
			}
			else if rep>0 && rep < re.prog[tmp_pc].rep_min {
				//println("ist_quant_ng UNDER THE MINIMUM g.i: $group_index")

				// check if we are inside a group, if yes exit from the nested groups
				if group_index > 0{
					group_index--
					pc = tmp_pc
					m_state = .ist_quant_ng //.ist_next
					continue
				}

				if group_index == 0 {
					group_index--
					pc = tmp_pc // TEST
					m_state = .ist_next
					continue
				}

				result = no_match_found
				m_state = .stop
				continue
			}
			else if rep==0 && rep < re.prog[tmp_pc].rep_min {
				//println("ist_quant_ng c_zero UNDER THE MINIMUM g.i: $group_index")

				if group_index > 0{
					group_index--
					pc = tmp_pc
					m_state = .ist_quant_ng //.ist_next
					continue
				}

				result = no_match_found
				m_state = .stop
				continue
			}

			//println("DO NOT STAY HERE!! {${re.prog[tmp_pc].rep_min},${re.prog[tmp_pc].rep_max}}:$rep")
			/* UNREACHABLE */
			return err_internal_error, i

		}
		// ist_quant_pg
		else if m_state == .ist_quant_pg {
			//println(".ist_quant_pg")
			mut tmp_pc := pc
			if group_index >= 0 {
				tmp_pc = group_data[group_index]
			}

			rep := re.prog[tmp_pc].group_rep

			if rep < re.prog[tmp_pc].rep_min {
				//println("ist_quant_pg UNDER RANGE")
				pc = re.prog[tmp_pc].goto_pc
				m_state = .ist_next
				continue
			}
			else if rep == re.prog[tmp_pc].rep_max {
				//println("ist_quant_pg MAX RANGE")
				re.prog[tmp_pc].group_rep = 0 // clear the repetitions
				group_index--
				m_state = .ist_next
				continue
			}
			else if rep >= re.prog[tmp_pc].rep_min {
				//println("ist_quant_pg IN RANGE group_index:$group_index")

				// check greedy flag, if true exit on minimum
				if re.prog[tmp_pc].greedy == true {
					re.prog[tmp_pc].group_rep = 0 // clear the repetitions
					group_index--
					m_state = .ist_next
					continue
				}

				pc = re.prog[tmp_pc].goto_pc - 1
				group_index--
				m_state = .ist_next
				continue
			}

			/* UNREACHABLE */
			//println("PANIC3!! state: $m_state")
			return err_internal_error, i
		}

		// ist_quant_n
		else if m_state == .ist_quant_n {
			rep := re.prog[pc].rep
			//println("Here!! PC $pc is_next_or: ${re.prog[pc].next_is_or}")

			// zero quantifier * or ?
			if rep == 0 && re.prog[pc].rep_min == 0 {
				//println("ist_quant_n c_zero RANGE MIN")
				m_state = .ist_next // go to next ist
				continue
			}
			// match + or *
			else if rep >= re.prog[pc].rep_min {
				//println("ist_quant_n MATCH RANGE")
				m_state = .ist_next
				continue
			}

			// check the OR if present
			if re.prog[pc].next_is_or {
				//println("OR present on failing")
				state.match_index = -1
				m_state = .ist_next
				continue
			}

			// we are in a group manage no match from here
			if group_index >= 0 {
				//println("ist_quant_n FAILED insied a GROUP group_index:$group_index")
				m_state = .ist_quant_ng
				continue
			}

			// no other options
			//println("ist_quant_n no_match_found")
			result = no_match_found
			m_state = .stop
			continue
			//return no_match_found, 0
		}

		// ist_quant_p
		else if m_state == .ist_quant_p {
			// exit on first match
			if (re.flag & f_efm) != 0 {
				return i,i+1
			}

			rep := re.prog[pc].rep

			// under range
			if rep > 0 && rep < re.prog[pc].rep_min {
				//println("ist_quant_p UNDER RANGE")
				m_state = .ist_load // continue the loop
				continue
			}

			// range ok, continue loop
			else if rep >= re.prog[pc].rep_min && rep < re.prog[pc].rep_max {
				//println("ist_quant_p IN RANGE")

				// check greedy flag, if true exit on minimum
				if re.prog[pc].greedy == true {
					m_state = .ist_next
					continue
				}
				m_state = .ist_load
				continue
			}

			// max reached
			else if rep == re.prog[pc].rep_max {
				//println("ist_quant_p MAX RANGE")
				m_state = .ist_next
				continue
			}

		}
		/* UNREACHABLE */
		//println("PANIC4!! state: $m_state")
		return err_internal_error, i
	}

	// Check the results
	if state.match_index >= 0 {
		if group_index < 0 {
			//println("OK match,natural end [$first_match,$i]")
			return first_match, i
		} else {
			//println("Skip last group")
			return first_match,group_stack[group_index--]
		}
	}
	//println("no_match_found, natural end")
	return no_match_found, 0
}

/*

Public functions

*/

//
// Inits
//

// regex create a regex object from the query string
pub fn regex(in_query string) (RE,int,int){
	mut re := RE{}
	re.prog = [Token{}].repeat(in_query.len+1)
	re.cc = [CharClass{}].repeat(in_query.len+1)
	re.group_max_nested = 8

	re_err,err_pos := re.compile(in_query)
	return re, re_err, err_pos
}

// new_regex create a RE of small size, usually sufficient for ordinary use
pub fn new_regex() RE {
	return new_regex_by_size(1)
}

// new_regex_by_size create a RE of large size, mult specify the scale factor of the memory that will be allocated
pub fn new_regex_by_size(mult int) RE {
	mut re := RE{}
	re.prog = [Token{}].repeat(max_code_len*mult)       // max program length, default 256 istructions
	re.cc = [CharClass{}].repeat(max_code_len*mult)     // char class list
	re.group_max_nested = 3*mult                        // max nested group

	return re
}

//
// Matchers
//

pub fn (mut re RE) match_string(in_txt string) (int,int) {
	start, end := re.match_base(in_txt.str,in_txt.len)
	if start >= 0 && end > start {
		if (re.flag & f_ms) != 0 && start > 0 {
			return no_match_found, 0
		}
		if (re.flag & f_me) != 0 && end < in_txt.len {
			if in_txt[end] in new_line_list {
				return start, end
			}
			return no_match_found, 0
		}
		return start, end
	}
	return start, end
}

//
// Finders
//

// find try to find the first match in the input string
pub fn (mut re RE) find(in_txt string) (int,int) {
	old_flag := re.flag
	re.flag |= f_src  // enable search mode
	start, end := re.match_base(in_txt.str, in_txt.len)
	re.flag = old_flag
	if start >= 0 && end > start {
		return start,end
	}
	return no_match_found, 0
}

// find all the non overlapping occurrences of the match pattern
pub fn (mut re RE) find_all(in_txt string) []int {
	mut i := 0
	mut res := []int{}
	mut ls := -1
	for i < in_txt.len {
		s,e := re.find(in_txt[i..])
		if s >= 0 && e > s && i+s > ls {
			//println("find match in: ${i+s},${i+e} [${in_txt[i+s..i+e]}] ls:$ls")
			res << i+s
			res << i+e
			ls = i+s
			i = i+e
			continue
		} else {
			i++
		}

	}
	return res
}

// replace return a string where the matches are replaced with the replace string
pub fn (mut re RE) replace(in_txt string, repl string) string {
	pos := re.find_all(in_txt)
	if pos.len > 0 {
		mut res := ""
		mut i := 0

		mut s1 := 0
		mut e1 := in_txt.len

		for i < pos.len {
			e1 = pos[i]
			res += in_txt[s1..e1] + repl
			s1 = pos[i+1]
			i += 2
		}

		res += in_txt[s1..]
		return res
	}
	return in_txt
}

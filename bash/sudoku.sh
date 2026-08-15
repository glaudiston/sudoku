#!/usr/bin/env bash
#
# This is a Sudoku game implementation. see README.md for user friendly info;
# Author: Glaudiston Gomes
# License: MIT
#
# Dependencies:
# - flock (util-linux)

UNAME=$(uname);
[[ "$UNAME" == "Darwin" ]] && {
	which flock 2>/dev/null || brew install flock
}

[[ -d /dev/shm ]] && SHM_DIR=/dev/shm || SHM_DIR=/tmp
declare base_folder;
relative_realpath(){
	realpath --relative-to . $1 2>/dev/null || realpath $1
}
base_folder="$(dirname "$(realative_realpath "${BASH_SOURCE[0]}")")";

# force submodule update if needed to help new users
ls "${base_folder}/logger/bash/logger.sh" >/dev/null || git -C "${base_folder}" submodule update --init --recursive

cleanup(){
	echo -en "${TERM_LINE_WRAP_ON}${TERM_ALT_BUFFER_OFF}${TERM_CURSOR_ON}";
	trap -p
}

#trap cleanup EXIT TERM QUIT ABRT SEGV;

set -euo pipefail;
export LOG_MIME="file/jsonl";
export LOG_FILE="${base_folder}/logfile.jsonl";

. "$(dirname "$(realpath --relative-to . "${BASH_SOURCE[0]}")")/logger/bash/logger.sh";
. "$(dirname "$(realpath --relative-to . "${BASH_SOURCE[0]}")")/termsdk/ansi_term_codes.sh"

term_title "SUDOKU"
echo -en "${TERM_ALT_BUFFER_ON}${TERM_LINE_WRAP_OFF}${TERM_CURSOR_OFF}";

declare -axg values;
#xd HexDump
xd(){
	local i;
	for (( i=0; i<${#1}; i++)); do
		printf %x "'${1:$i:1}"
	done;
}
declare xd_a;
xd_a=$(xd "a");
declare xd_A
xd_A=$(xd "A");
set_blank_values(){
	local i;
	for ((i=0;i<9*9;i++)); do
		values[i]="";
	done;
}
set_blank_values
declare -ag annotations=()

# get_values: given a type(row, column or bloc) return an array of all set items;
get_values(){
	debug "get_values $*"
	local x;
	local y;
	local slice_type=$1;
	if [[ "$slice_type" == "row" ]]; then
		y="$2";
		for (( x=0; x<9; x++ ));
		do
			echo "${values[x+y*9]}";
		done;
		return;
	fi;
	if [[ "$slice_type" == "column" ]]; then
		x="$2";
		for (( y=0; y<9; y++ ));
		do
			echo "${values[x+y*9]}";
		done;
		return;
	fi;
	if [[ "$slice_type" == "bloc" ]]; then
		for (( i=0; i<9; i++ ));
		do
			x=$(( ($3/3) * 3 + (i%3) ))
			y=$(( ($2/3) * 3 + (i/3) ))
			echo "${values[x+y*9]}";
		done;
		return;
	fi;
	error "unsupported slice_type $slice_type";
}

count_dupl(){
	local -n array=$1;
	local v=${2:-""};
	local count=0;
	local i;
	#info "testing array [$1] for [$v]; array has [${#array[@]}] items";
	for (( i=0; i<${#array[@]}; i++ ));
	do
		if [[ "$v" == "${array[i]}" ]]; then
			#info "found item $v, count is $count";
			(( count++ ));
		fi;
	done;
	echo $count;
}

declare VALID=0;
declare EMPTY=$VALID;
declare DUPLICATED_ROW=1;
declare DUPLICATED_COLUMN=2;
declare DUPLICATED_BLOCK=4;

cell_redraw_v(){
	debug "call_redraw_v $*"
	local -n array=$1;
	local i;
	local v=$2;
	local level=$4;
	(( level > 0 )) && return;
	for (( i=0; i<9; i++)); do
		if [[ "${array[i]}" == "$v" ]]; then
			case $1 in 
				row)
					x=$i;
					y=$3;
					;;
				col)
					x=$3;
					y=$i;
					;;
				bloc)
					local blocN=$3;
					x=$(( blocN * 3 + (i%3) ))
					y=$(( blocN * 3 + (i/3) ))
					;;
			esac
			cell_draw "$x" "$y" "$v" $((level+1));
		fi;
	done;
}

validate(){
	local x="$1";
	local y="$2";
	local v="$3";
	local level="$4";
	local rv=0;
	if [[ ! "$v" =~ ^[1-9]$ ]]; then
		return "$EMPTY";
	fi;
	debug "validate $*"
	declare -a row;
	declare -a col;
	declare -a bloc;
	mapfile -t row < <(get_values row "$y")
	info "values=${values[*]}"
	info "row_values[#${#row[@]}]=[${row[*]}]"
	count_row=$(count_dupl row "$v");
	mapfile -t col < <(get_values column "$x");
	count_col=$(count_dupl col "$v")
	info "col_values[#${#col[@]}]=[${col[*]}] count_col=$count_col"
	mapfile -t bloc < <(get_values bloc "$x" "$y");
	info "bloc_values[#${#bloc[@]}]=[${bloc[*]}]"
	count_bloc=$(count_dupl bloc "$v")
	if (( count_row > 1 )); then
		cell_redraw_v row "$v" "$y" "$level";
		(( rv |= DUPLICATED_ROW ))
	fi;
	if (( count_col > 1 )); then
		cell_redraw_v col "$v" "$x" "$level";
		(( rv |= DUPLICATED_COLUMN ))
	fi;
	if (( count_bloc > 1 )); then
		local blocN=$(( (1+x/3) * (1+y/3) -1));
		cell_redraw_v bloc "$v" "$blocN" "$level";
		(( rv |= DUPLICATED_BLOCK ))
	fi;
	return $rv;
}

char(){
	echo -ne "$(printf '\\x%x' "$1")";
}

cell_draw(){
	local x=$1
	local y=$2
	local level=$4;
	local v;
	local bg;
	local fg;
	debug "cell_draw $*"

	v=$(printf " %1s " "$3");
	headers=$(( y == -1 || x == -1 ));
	if (( headers )); then
		v="   ";
		if (( x > -1 )); then
			v=" $(char $(( 16#$xd_A + x))) ";
		elif (( y > -1 )); then
			v=" $(char $(( 16#$xd_a + y))) ";
		fi;
		bg=$(term_color rgb background 20 20 20);
		fg=$(term_color rgb foreground 40 40 70);
	else
		if (( (x/3) % 2 == (y/3) % 2 )); then
			bg=$(term_color rgb background 30 30 30);
			fg=$(term_color rgb foreground 70 70 70);
		else
			bg=$(term_color rgb background 20 20 20);
			fg=$(term_color rgb foreground 70 70 70);
		fi;
		if [[ "$4" -lt 2 ]]; then
			if ! validate "$x" "$y" "${v// /}" "$level"; then
				fg=$(term_color rgb foreground 130 0 0);
			fi;
		fi;
	fi;
	(flock -x 3;
		move_to_cell "$x" "$y";
		echo -ne "$bg$fg$v$TERM_COLOR_RESET";
	) 3>"$SHM_DIR/sudoku.drawlock";
}

move_to_cell(){
	local cell_width=3;
	local cell_height=1;
	local x="$1";
	local y="$2";
	term_move "$(((2+x)*cell_width -2))" "$(((2+y)*cell_height))";
}

redraw(){
	clear;
	local y;
	local x;
	local v;
	for (( y=-1; y<9; y++ )); do
		for (( x=-1; x<9; x++)); do {
			v="${values[x+y*9]}";
			cell_draw "$x" "$y" "$v" 0;
		} &
		done;
	done;
	wait
	term_move 0 0
}

declare value_highlighted=0
cell_highlight(){
	(flock -x 4
	move_to_cell "$1" "$2";
	local bg
	bg=$(term_color rgb background 100 80 50);
	echo -ne "$bg $3 $TERM_COLOR_RESET";
	) 4>"$SHM_DIR/sudoku.draw-highlight-lock"
}
highlight_bloc(){
	local blocN="$1"
}
highlight_col(){
	:
}
highlight_row(){
	local x="$1"
}
highlight_value(){
	local v="$1";
	local x;
	local y;
	for (( i=0; i<9*9; i++ )){
		if [[ "${values[i]}" == "$value_highlighted" ]]; then
			x=$((i%9));
			y=$((i/9));
			cell_draw "$x" "$y" "${value_highlighted}" 0;
		fi;
		if [[ "${values[i]}" == "$v" ]]; then
			x=$((i%9));
			y=$((i/9));
			cell_highlight "$x" "$y" "$v" &
		fi;
	}
	value_highlighted="$v"
	wait;
}


declare save_folder=${base_folder}/save;
declare default_save_file=${save_folder}/sudoku.save;
declare current_save_file=$default_save_file;
load(){
	local save_file=$1;
	mkdir -p "${save_folder}";
	[[ -f "${save_file}" ]] && mapfile -t values <"${save_file}"
	redraw
}
save(){
	mkdir -p save;
	printf "%s\n" "${values[@]}" >"${default_save_file}"
}
quit(){
	exit 0;
}

set_x(){
	# parse colum (x)
	if [[ "$REPLY" =~ ^[A-I]$ ]]; then # col (x)
		ix="$REPLY";
		xdx=$(xd "$ix");
		x="$(( 16#$xdx - 16#$xd_A))"
		highlight_col "$x";
	fi;
}
set_y(){
	# parse row (y)
	if [[ "$REPLY" =~ ^[a-i]$ ]]; then # row (y)
		iy="$REPLY";
		xdy=$(xd "$iy");
		y="$(( 16#$xdy - 16#$xd_a))";
		highlight_row "$y";
	fi;
}
set_v(){
	# parse / set value
	if [[ "$REPLY" =~ ^[0-9]$ && ! -z "$ix" && ! -z "$iy" ]]; then
		v="${REPLY}"
		values[x+y*9]="$v";
		cell_draw "$x" "$y" "$v" 0;
		term_move 0 0
		ix="";
		iy="";
		save;
		local blocN="$(( (x%3+1) * (y/3+1) -1 ))";
		highlight_bloc "$blocN";
		x=-1;
		y=-1;
	fi;
	highlight_value "$REPLY"
}

declare -A keybind;
keybind["s"]=save
keybind["l"]=load
keybind["[A-I]"]=set_x
keybind["[a-i]"]=set_y
keybind["[0-9]"]=set_v
keybind["q"]=quit;

read_input(){
	local ix="";
	local iy="";
	local xdx;
	local xdy;
	local x=-1;
	local y=-1;
	local v;
	local i;
	while read -srn 1; do
		for k in "${!keybind[@]}"; do
			[[ "$REPLY" =~ $k ]] && ${keybind[$k]} "$REPLY";
		done;
	done
}
load "${default_save_file}"
read_input
wait;

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
	which flock &>/dev/null || brew install flock
}

[[ -d /dev/shm ]] && SHM_DIR=/dev/shm || SHM_DIR=/tmp
declare base_folder;
sudoku_relative_realpath(){
	realpath --relative-to . "$1" 2>/dev/null || realpath "$1"
}
base_folder="$(dirname "$(sudoku_relative_realpath "${BASH_SOURCE[0]}")")";

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

. "$(dirname "$(sudoku_relative_realpath "${BASH_SOURCE[0]}")")/logger/bash/logger.sh";
. "$(dirname "$(sudoku_relative_realpath "${BASH_SOURCE[0]}")")/termsdk/ansi_term_codes.sh"

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
declare BLANK_COUNT_IDX=81;
declare ERROR_COUNT_IDX=82;
declare SPENT_TIME_IDX=83;
declare START_TIME_IDX=84; # game creating
declare LAST_SAVE_TIME_IDX=85;
declare LAST_OPEN_TIME_IDX=86; # used to calc the spent time
declare LAST_FIELD_IDX=$LAST_OPEN_TIME_IDX;
set_fields(){
	local -n r_values=$1;
	local now;
	now=$(printf "%(%s)T" -1)
	r_values[BLANK_COUNT_IDX]=81;
	r_values[ERROR_COUNT_IDX]=0;
	r_values[SPENT_TIME_IDX]=0;
	r_values[START_TIME_IDX]=$now;
	# shellcheck disable=SC2034
	r_values[LAST_SAVE_TIME_IDX]=${r_values[START_TIME_IDX]};
	r_values[LAST_OPEN_TIME_IDX]=${r_values[START_TIME_IDX]};
}
set_blank_values(){
	local i;
	for ((i=0;i<9*9;i++)); do
		values[i]="";
	done;
	set_fields values;
}
set_blank_values
# shellcheck disable=SC2034
declare -ag annotations=()

# get_values: given a type(row, column or bloc) return an array of all set items;
get_values(){
	debug "get_values $*"
	local _get_values_x;
	local _get_values_y;
	local slice_type=$1;
	if [[ "$slice_type" == "row" ]]; then
		local idx="$(( $2 * 9 ))";
		local rv=( "${values[@]:$idx:9}" );
		info "get_values $* == [${rv[@]}]"
		printf "%s\n" "${rv[@]}"
		return;
	fi;
	if [[ "$slice_type" == "column" ]]; then
		_get_values_x="$2";
		local rv=()
		for (( _get_values_y=0; _get_values_y<9; _get_values_y++ ));
		do
			rv[_get_values_y]="${values[_get_values_x+_get_values_y*9]}";
		done;
		info "get_values $* == [${rv[@]}]"
		printf "%s\n" "${rv[@]}"
		return;
	fi;
	if [[ "$slice_type" == "bloc" ]]; then
		local rv=();
		local i=0;
		for (( i=0; i<9; i++ ));
		do
			_get_values_x=$(( ($3/3) * 3 + (i%3) ))
			_get_values_y=$(( ($2/3) * 3 + (i/3) ))
			rv[i]="${values[_get_values_x+_get_values_y*9]}";
		done;
		info "get_values $* == [${rv[@]}]"
		printf "%s\n" "${rv[@]}"
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
	local x;
	local y;
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
					x=$(( ((blocN) % 3) * 3 + (i%3) ))
					y=$(( ((blocN) % 3) * 3 + (i/3) ))
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
	[[ $1 == 25 ]] && error "unexpected $*"
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
		[[ "$v" == " 0 " ]] && v="   "
	fi;
	(flock -x 3;
		move_to_cell "$x" "$y";
		echo -ne "$bg$fg$v$TERM_COLOR_RESET";
	) 3>"$SHM_DIR/sudoku.drawlock";
}

declare table_x_pad=1
declare table_y_pad=2

move_to_cell(){
	local cell_width=3;
	local cell_height=1;
	local x="$1";
	local y="$2";
	term_move "$(( table_x_pad + (2+x)*cell_width -2 ))" "$(( table_y_pad + (2+y)*cell_height ))";
}

render_frame(){
	term_move 0 0
	echo "Sudoku:"
	term_move $((table_x_pad)) $((table_y_pad))
	bg=$(term_color rgb background 20 20 20);
	fg=$(term_color rgb foreground 40 40 70);
	printf "$bg$fg%s%30s%s\n" "╭" "" "╮"| sed "s/ /─/g"
	local i;
	for (( i=0; i<10; i++)); do
	printf "%s%30s%s\n" "│" "" "│"
	done;
	printf "%s%30s%s" "╰" "" "╯"| sed "s/ /─/g"
	#printf "%s" "ꜜ6️⃣9️⃣9️⃣";
}


redraw(){
	clear;
	render_frame;
	ui_status "Rendering.... Please wait...(bash is slow)"
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
	ui_help;
	refresh_current_game_info
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
	local x=$1;
	local y=0;
	for (( y=0; y<9; y++ )) 
	do
		:
	done;
}
highlight_row(){
	local x="$1"
}
highlight_value(){
	local v="$1";
	if [[ "$v" == "0" ]]; then
		return;
	fi;
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
declare save_id_file=${save_folder}/save_id;

get_game_id(){
	local gameid;
	mkdir -p "${save_folder}";
	[ -f "$save_id_file" ] || echo "0" > "$save_id_file";
	read -r gameid <"$save_id_file"
	echo -n "${gameid:-0}"
}

get_save_file(){
	local save_file;
	local gameid;
	gameid="$(get_game_id)";
	save_file="${save_folder}/sudoku.${gameid}.save"
	echo -n "$save_file"
}

max_game_id(){
	declare f;
	for f in "$save_folder/sudoku."*'.save';
	do
		echo "$f" |
			grep -o '[0-9]*';
	done |
		sort -n |
			tail -1;
}

new(){
	local max_game_id;
	max_game_id=$(max_game_id)
	echo -n "$((max_game_id+1))" >"$save_id_file";
	load
}

elapsed_text(){
	local elap=$1
	local seconds=$elap;
	if [[ seconds -lt 99 ]]; then
		echo "${seconds}s"
		return;
	fi;
	local minutes=$((seconds / 60));
	if [[ $minutes -lt 99 ]]; then
		echo "${minutes}m";
		return;
	fi;
	local hours=$((minutes / 60));
	if [[ $hours -lt 24 ]]; then
		echo "${hours}H"
		return;
	fi;
	local days=$((hours / 24));
	if [[ $days -lt 7 ]]; then
		echo "${days}D"
		return;
	fi;
	local weeks=$(( days / 7 ));
	if [[ $weeks -lt 5 ]]; then
		echo "${weeks}W";
		return
	fi;
	local months=$(( days / 30 ));
	if [[ $months -lt 12 ]]; then
		echo "${months}M"
		return
	fi;
	local years=$(( months / 12 ))
	echo "👴 ${years}Y"
}
elapsed(){
	local t1=$1;
	local now;
	now=$(printf "%(%s)T" -1)
	local t2=$now;
	[[ ${#@} -gt 1 ]] && t2=${2};
	local elap=$((t2 - t1));
	elapsed_text $elap;
}

game_info(){
	local -n data="$1"
	local percent=$(( 100 - data[BLANK_COUNT_IDX] * 100 / 81))
	local errcnt=${data[ERROR_COUNT_IDX]:0}
	local spent_time=${data[SPENT_TIME_IDX]:0}
	local spent_time;
	spent_time="$(elapsed_text ${data[SPENT_TIME_IDX]})";
	local elapsed_since_saved=0;
	local elapsed_since_saved_text=""
	local now;
	printf -v now "%(%s)T" -1;
	if [[ $(( now - data[LAST_SAVE_TIME_IDX] )) -gt 300 ]]; then
		elapsed_since_saved="$(elapsed "${data[LAST_SAVE_TIME_IDX]}")";
		elapsed_since_saved_text=" 💾:$elapsed_since_saved"
	fi;
	local errs="";
	[[ $errcnt -gt 0 ]] && errs=" ⛔:$errcnt"
	printf "%i%% ⏱️:%s%s%s  " "$percent" "$spent_time" "$errs" "$elapsed_since_saved_text"
}

save_info(){
	local save_file=$1;
	if [[ "$save_file" == "" ]]; then
		echo "empty";
		return;
	fi;
	declare -ax saved_values;
	mapfile -t saved_values <"$save_file";
	if [[ ${#saved_values[@]} -lt $LAST_FIELD_IDX ]]; then
		set_fields saved_values
	fi;
	game_info saved_values
}

show_load_menu(){
	local files_per_page=9
	local page=0;
	declare -a save_files;
	mapfile -t save_files < <(ls -t1 "$save_folder/sudoku."*".save");
	info "found ${#save_files[@]}"
	last_page=$(( ${#save_files[@]} / files_per_page ));
	while true; do
	{
		[[ $page -lt 0 ]] && page=0;
		[[ $page -gt $last_page ]] && page=$last_page;
		ui_status "Listing saves..."
		local i;
		local f="";
		for (( i=0; i<9; i++ )); do
			term_move 2 $((1+i+table_y_pad))
			f="";
			if [[ $(( i*page+i )) -lt ${#save_files[@]} ]]; then
				f="${save_files[$((i*page+i))]}";
			fi;
			printf " %i %-27s" "$((i+1))" "$(save_info "$f")"; 
		done
		term_move 11 11
		printf "[page %i/%i]" $((page+1)) $((last_page+1))
		ui_status "Select your save file"
		term_move 1 15
		printf "n\tNext page"
		printf "p\tPrevious Page"
		printf "c\tCancel\n"
		printf "q\tQuit"
		local opt;
		read -srn 1 opt;
		if [[ "$opt" =~ ^(n| )$ ]]; then
			page=$((page+1))
			continue;
		fi;
		if [[ "$opt" =~ ^[bp]$ ]]; then
			page=$((page-1));
			continue;
		fi;
		if [[ "$opt" == "c" || "$opt" == "\x1b" ]]; then
			redraw;
			return;
		fi;
		if [[ "$opt" == "q" ]]; then
			quit;
		fi;
		if [[ "$opt" =~ ^[1-9]$ ]]; then
			clear
			i=$(( opt*(page)+opt-1 ))
			if [[ ! $i -lt ${#save_files[@]} ]]; then
				new
				break;
			fi;
			f=${save_files[i]};
			echo "$f"| grep -o "[0-9]*" > "${save_id_file}"
			break;
		fi;
	};
	done;
	load;
}

declare pause_time=0

pause_toggle(){
	[[ $pause_time -eq 0 ]] && pause || resume 
}

pause(){
	pause_time="$(printf "%(%s)T" -1)";
	local i;
	for ((i=0;i<10;i++));do
		term_move 2 $(( 1+i+table_y_pad ))
		printf "%30s" ""
	done;
	term_move 2 5
	printf "    G A M E   P A U S E D   "
}

update_spent_time(){
	local ref_time;
	local now;
	now=$(printf "%(%s)T" -1);
	ref_time=$now
	if [[ $pause_time -gt 0 ]]; then
		ref_time=$pause_time;
	fi
	values[SPENT_TIME_IDX]=$(( values[SPENT_TIME_IDX] + (ref_time - values[LAST_OPEN_TIME_IDX]) ))
	values[LAST_OPEN_TIME_IDX]=$now
}

resume(){
	redraw;
	local now;
	now=$(printf "%(%s)T" -1);
	values[LAST_OPEN_TIME_IDX]=$now
	pause_time=0;
}

load_menu(){
	pause
	save
	show_load_menu
	resume
}

load(){
	local save_file;
	ui_status "Loading..."
	save_file="$(get_save_file)";
	set_blank_values
	[[ -f "${save_file}" ]] && mapfile -t values <"${save_file}"
	if [[ ${#values[@]} -lt $LAST_FIELD_IDX ]]; then
		set_fields values
	fi;
	values[LAST_OPEN_TIME_IDX]=$(printf "%(%s)T" -1)
	redraw
}

save(){
	local save_file;
	save_file=$(get_save_file);
	update_spent_time;
	local now=$(printf "%(%s)T" -1)
	values[LAST_SAVE_TIME_IDX]=$now
	printf "%s\n" "${values[@]}" >"${save_file}"
	ui_status "Saved"
	sleep 1;
}

declare last_status_size=0
ui_status() {
	term_move $(( table_x_pad + 2 )) $(( table_y_pad + 13 ));
	local text="$*"
	printf "%-${last_status_size:0}s" "$*"
	last_status_size=${#text}
	term_move 2 0
}

ui_help(){
	term_move 0 $(( table_y_pad + 15 ))
	for v in "${!keybind[@]}";
	do
		echo -e "$v\t${keybind[$v]}"
	done;
	term_move 0 0
}

quit(){
	save
	reset;
	exit 0;
}

set_x(){
	# parse colum (x)
	if [[ ! "$REPLY" =~ ^[A-I]$ ]]; then
		# invalid
		return;
	fi;
	# col (x)
	ix="$REPLY";
	xdx=$(xd "$ix");
	old_x="$x"
	x="$(( 16#$xdx - 16#$xd_A))"
	if [[ "$old_x" == "$x" ]]; then
		return;
	fi;
	highlight_col "$x";
	local blocN="$(( (x%3+1) * (y/3+1) -1 ))";
	highlight_bloc "$blocN";
}

set_y(){
	# parse row (y)
	if [[ ! "$REPLY" =~ ^[a-i]$ ]]; then
		# invalid
		return;
	fi;
	# row (y)
	iy="$REPLY";
	xdy=$(xd "$iy");
	old_y="$y"
	y="$(( 16#$xdy - 16#$xd_a))";
	if [[ "$old_y" == "$y" ]]; then
		return;
	fi;
	highlight_row "$y";
	local blocN="$(( (x%3+1) * (y/3+1) -1 ))";
	highlight_bloc "$blocN";
}

refresh_current_game_info(){
	term_move 9 0
	game_info values
}
set_v(){
	# parse / set value
	if [[ "$REPLY" =~ ^[0-9]$ && ! -z "$ix" && ! -z "$iy" ]]; then
		v="${REPLY}"
		highlight_value "$v"
		local p_v=${values[x+y*9]};
		if [[ "$p_v" == "$v" ]]; then
			highlight_value "$v";
			return;
		fi;
		if [[ "$p_v" == "" || "$p_v" == 0 ]] && [[ "$v" != "0" ]]; then
			values[BLANK_COUNT_IDX]=$(( values[BLANK_COUNT_IDX] -1 ))
			if ! validate "$x" "$y" "$v" 0; then
				values[ERROR_COUNT_IDX]=$(( values[ERROR_COUNT_IDX]+1 ));
			fi;
		fi;
		if [[ "$p_v" =~ ^[1-9]$ ]] && [[ "$v" == "0" ]]; then
			values[BLANK_COUNT_IDX]=$(( values[BLANK_COUNT_IDX] +1 ))
		fi;
		values[x+y*9]="$v";
		cell_draw "$x" "$y" "$v" 0;
		refresh_current_game_info
		ix="";
		iy="";
		save;
		x=-1;
		y=-1;
	fi;
}

declare -A keybind;
keybind["s"]=save
keybind["l"]=load_menu
keybind["n"]=new;
#keybind["j"]=hint_one;
#keybind["k"]=auto_solve;
keybind["[A-I]"]=set_x
keybind["[a-i]"]=set_y
keybind["[0-9]"]=set_v
keybind["q"]=quit;
keybind["p"]=pause_toggle

read_input(){
	local ix="";
	local iy="";
	local xdx;
	local xdy;
	local x=-1;
	local y=-1;
	local v;
	local i;
	ui_status "Ready! Waiting your call..."
	while read -srn 1; do
		ui_status "Processing your input... Please wait..."
		for k in "${!keybind[@]}"; do
			[[ "$REPLY" =~ $k ]] && ${keybind[$k]} "$REPLY";
		done;
		ui_status "Ready! Waiting your call..."
	done
}

render_frame;
load
read_input
wait;

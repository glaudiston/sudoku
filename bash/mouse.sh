#!/usr/bin/env bash

FunctionExists() {
	declare -f -F "$1" > /dev/null
	return $?
}

# Enable capture
printf '\033[?1000;1002;1006;1015h'

# Declare binds
declare -A Bindings=(
	['<0;']='ReadInput MouseClick1 \<0;'
	['<1;']='ReadInput MouseClick2 \<1;'
	['<2;']='ReadInput MouseClick3 \<2;'
	['<32;']='ReadInput MouseDrag1 \<32;'
	['<33;']='ReadInput MouseDrag2 \<33;' # Supported in Alacritty
	['<34;']='ReadInput MouseDrag3 \<34;'
	['<64;']='ReadInput MouseScrollUp \<64;'
	['<65;']='ReadInput MouseScrollDown \<65;'
)

# Apply binds
for KeySeq in "${!Bindings[@]}"; do
	bind -x "\"\033[$KeySeq\":${Bindings[$KeySeq]}"
done

ReadInput() {
	declare -A Input=()
	Type=$1
	Input['Type']=$Type
	Axis='X'
	Buffer=''

	while read -r -n 1 -s Key; do
		Buffer="$Buffer$Key"

		if [[ $Key == ';' ]]; then
			Axis='Y'
		elif [[ $Key =~ [0-9] ]]; then
			Input[$Axis]="${Input[$Axis]}$Key"
		else
			Input['State']=$Key
			break
		fi
	done

	# If a function for the type of mouse input exists, run it.
	FunctionExists "${Type}" && ${Type}
}

# Example functions
MouseClick1() {
	echo "Mouse click 1 at ${Input['X']} ${Input['Y']} ${Input['State']}"
}

MouseClick3() {
	echo "Mouse click 3 at ${Input['X']} ${Input['Y']} ${Input['State']}"
}

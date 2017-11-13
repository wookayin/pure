# Pure THEME
# A customized version of @wookayin
# https://github.com/wookayin/pure
#
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# temporarily disable automatic git fetch in background
PURE_GIT_PULL=0

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pure_human_time_to_var() {
	local human=" " total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	# store human readable time in variable as specified by caller
	typeset -g "${var}"="${human}"
}

# stores (into prompt_pure_cmd_exec_time) the exec time of the last command if set threshold was exceeded
prompt_pure_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_pure_cmd_timestamp:-$EPOCHSECONDS} ))
	prompt_pure_cmd_exec_time=
	(( elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5} )) && {
		prompt_pure_human_time_to_var $elapsed "prompt_pure_cmd_exec_time"
	}
}

prompt_pure_clear_screen() {
	# enable output to terminal
	zle -I
	# clear screen and move cursor to (0, 0)
	print -n '\e[2J\e[0;0H'
	# print preprompt
	prompt_pure_preprompt_render precmd
}

prompt_pure_set_title() {
	# emacs terminal does not support settings the title
	(( ${+EMACS} )) && return

	# do not set the title in a tmux pane
	[[ -n $TMUX_PANE ]] && return

	# tell the terminal we are setting the title
	print -n '\e]0;'
	# show hostname if connected through ssh
	[[ -n $SSH_CONNECTION ]] && print -Pn '(%m) '
	case $1 in
		expand-prompt)
			print -Pn $2;;
		ignore-escape)
			print -rn $2;;
	esac
	# end set title
	print -n '\a'
}

prompt_pure_preexec() {
	# attempt to detect and prevent prompt_pure_async_git_fetch from interfering with user initiated git or hub fetch
	[[ $2 =~ (git|hub)\ .*(pull|fetch) ]] && async_flush_jobs 'prompt_pure'

	prompt_pure_cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title while a process is active
	prompt_pure_set_title 'ignore-escape' "$PWD:t: $2"
}

# string length ignoring ansi escapes
prompt_pure_string_length_to_var() {
	local str=$1 var=$2 length
	# perform expansion on str and check length
	length=${#${(S%%)str//(\%([KF1]|)\{*\}|\%[Bbkf])}}

	# store string length in variable as specified by caller
	typeset -g "${var}"="${length}"
}

prompt_pure_preprompt_render() {
	# store the current prompt_subst setting so that it can be restored later
	local prompt_subst_status=$options[prompt_subst]

	# make sure prompt_subst is unset to prevent parameter expansion in preprompt
	setopt local_options no_prompt_subst

	# check that no command is currently running, the preprompt will otherwise be rendered in the wrong place
	[[ -n ${prompt_pure_cmd_timestamp+x} && "$1" != "precmd" ]] && return

	# set color for git branch/dirty status, change color if status checking has been delayed
	local git_color="green"
	[[ -n ${prompt_pure_git_last_status_check_timestamp+x} ]] && git_color="red"

	# construct preprompt
	# -------------------
	local preprompt=""

	# username and machine
	local prompt_pure_username='%B%F{yellow}%n%f%b'
	[[ $UID -eq 0 ]] && prompt_pure_username='%F{white}%n%f' # root in white
	prompt_pure_username+='%F{242}@'          # dark grey
	prompt_pure_username+="%B%F{${PROMPT_HOST_COLOR:-cyan}}%m%f%b "
	preprompt+=$prompt_pure_username

	# path
	preprompt+="%B%F{red}%/%f%b "
	# git info (branch, etc.)
	preprompt+="%F{$git_color}${vcs_info_msg_0_}%f "
	# other information
	preprompt+="%F{cyan}${python_info}%f"
	preprompt+="%F{white}${cuda_info}%f"
	# execution time
	preprompt+="%F{yellow}${prompt_pure_cmd_exec_time}%f"


	# construct right-aligned prompts
	# -------------------------------
	pre_rprompt=''
	# git info (pull/push arrows)
	pre_rprompt+="%F{blue}${prompt_pure_git_arrows}%f"
	# git info (repository status, other than arrows)
	pre_rprompt+="${prompt_pure_git_status}"

	# merge left-prompt and right-prompt
	prompt_pure_string_length_to_var "${preprompt}" "preprompt_length"
	prompt_pure_string_length_to_var "${pre_rprompt}" "pre_rprompt_length"
	if (( ($preprompt_length - 1) % $COLUMNS + 1 + $pre_rprompt_length < $COLUMNS )); then
		local rprompt_padding_width=$(($COLUMNS-(${preprompt_length}+${pre_rprompt_length})%$COLUMNS))
		preprompt+="$(printf ' %.0s' {1..$rprompt_padding_width})${pre_rprompt}"
	fi

	# make sure prompt_pure_last_preprompt is a global array
	typeset -g -a prompt_pure_last_preprompt

	# if executing through precmd, do not perform fancy terminal editing
	if [[ "$1" == "precmd" ]]; then
		print -P "\n${preprompt}"
	else
		# only redraw if the expanded preprompt has changed
		[[ "${prompt_pure_last_preprompt[2]}" != "${(S%%)preprompt}" ]] || return

		# calculate length of preprompt and store it locally in preprompt_length
		integer preprompt_length lines
		prompt_pure_string_length_to_var "${preprompt}" "preprompt_length"

		# calculate number of preprompt lines for redraw purposes
		(( lines = ( preprompt_length - 1 ) / COLUMNS + 1 ))

		# calculate previous preprompt lines to figure out how the new preprompt should behave
		integer last_preprompt_length last_lines
		prompt_pure_string_length_to_var "${prompt_pure_last_preprompt[1]}" "last_preprompt_length"
		(( last_lines = ( last_preprompt_length - 1 ) / COLUMNS + 1 ))

		# clr_prev_preprompt erases visual artifacts from previous preprompt
		local clr_prev_preprompt
		if (( last_lines > lines )); then
			# move cursor up by last_lines, clear the line and move it down by one line
			clr_prev_preprompt="\e[${last_lines}A\e[2K\e[1B"
			while (( last_lines - lines > 1 )); do
				# clear the line and move cursor down by one
				clr_prev_preprompt+='\e[2K\e[1B'
				(( last_lines-- ))
			done

			# move cursor into correct position for preprompt update
			clr_prev_preprompt+="\e[${lines}B"
		# create more space for preprompt if new preprompt has more lines than last
		elif (( last_lines < lines )); then
			# move cursor using newlines because ansi cursor movement can't push the cursor beyond the last line
			printf $'\n'%.0s {1..$(( lines - last_lines ))}
		fi

		# disable clearing of line if last char of preprompt is last column of terminal
		local clr='\e[K'
		(( COLUMNS * lines == preprompt_length )) && clr=

		# modify previous preprompt
		print -Pn "${clr_prev_preprompt}\e[${lines}A\e[${COLUMNS}D${preprompt}${clr}\n"

		if [[ $prompt_subst_status = 'on' ]]; then
			# re-eanble prompt_subst for expansion on PS1
			setopt prompt_subst
		fi

		# redraw prompt (also resets cursor position)
		zle && zle .reset-prompt
	fi

	# store both unexpanded and expanded preprompt for comparison
	prompt_pure_last_preprompt=("$preprompt" "${(S%%)preprompt}")
}

prompt_pure_precmd() {
	# check exec time and store it in a variable
	prompt_pure_check_cmd_exec_time

	# by making sure that prompt_pure_cmd_timestamp is defined here the async functions are prevented from interfering
	# with the initial preprompt rendering
	prompt_pure_cmd_timestamp=

	# shows the full path in the title
	prompt_pure_set_title 'expand-prompt' '%~'

	# get vcs info
	vcs_info

	# get python info (virtualenv or anaconda)
	if [ -n "${VIRTUAL_ENV}" ]; then
		python_info="${VIRTUAL_ENV:t} "
	elif [ -n "${CONDA_DEFAULT_ENV}" ]; then
		python_info="conda:${CONDA_DEFAULT_ENV:t} "
	else
		python_info=""
	fi

	# nvidia-cuda information
	if [ ! -z "${CUDA_VISIBLE_DEVICES+1}" ]; then
		cuda_info="CUDA:$CUDA_VISIBLE_DEVICES "
	else
		unset cuda_info
	fi

	# preform async git status check and fetch
	prompt_pure_async_tasks

	# print the preprompt
	prompt_pure_preprompt_render "precmd"

	# remove the prompt_pure_cmd_timestamp, indicating that precmd has completed
	unset prompt_pure_cmd_timestamp
}

# fastest possible way to check git status (if repo is dirty, etc.)
prompt_pure_async_git_status() {
	setopt localoptions noshwordsplit
	local untracked_status=$1 dir=$2

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $dir

	# fetch git status information via prezto's git-info module.
	git-info on
	git-info
	echo ${git_info[rprompt]}
}

prompt_pure_async_git_fetch() {
	setopt localoptions noshwordsplit
	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $1

	# set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
	export GIT_TERMINAL_PROMPT=0
	# set ssh BachMode to disable all interactive ssh password prompting
	export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o BatchMode=yes"}

	command git -c gc.auto=0 fetch &>/dev/null || return 1

	# check arrow status after a successful git fetch
	prompt_pure_async_git_arrows $1
}

prompt_pure_async_git_arrows() {
	setopt localoptions noshwordsplit
	builtin cd -q $1
	command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_pure_async_tasks() {
	setopt localoptions noshwordsplit

	# initialize async worker
	((!${prompt_pure_async_init:-0})) && {
		async_start_worker "prompt_pure" -u -n
		async_register_callback "prompt_pure" prompt_pure_async_callback
		prompt_pure_async_init=1
	}

	# store working_tree without the "x" prefix
	local working_tree="${vcs_info_msg_1_#x}"

	# check if the working tree changed (prompt_pure_current_working_tree is prefixed by "x")
	if [[ ${prompt_pure_current_working_tree#x} != $working_tree ]]; then
		# stop any running async jobs
		async_flush_jobs "prompt_pure"

		# reset git preprompt variables, switching working tree
		unset prompt_pure_git_status
		unset prompt_pure_git_last_status_check_timestamp
		prompt_pure_git_arrows=

		# set the new working tree and prefix with "x" to prevent the creation of a named path by AUTO_NAME_DIRS
		prompt_pure_current_working_tree="x${working_tree}"
	fi

	# only perform tasks inside git working tree
	[[ -n $working_tree ]] || return

	async_job "prompt_pure" prompt_pure_async_git_arrows $working_tree

	async_job "prompt_pure" prompt_pure_async_git_status ${PURE_GIT_UNTRACKED_status:-1} $working_tree

	# do not preform git fetch if it is disabled or working_tree == HOME
	if (( ${PURE_GIT_PULL:-1} )) && [[ $working_tree != $HOME ]]; then
		# tell worker to do a git fetch
		async_job "prompt_pure" prompt_pure_async_git_fetch $working_tree
	fi
}

prompt_pure_check_git_arrows() {
	setopt localoptions noshwordsplit
	local arrows left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=${PURE_GIT_DOWN_ARROW:-⇣}
	(( left > 0 )) && arrows+=${PURE_GIT_UP_ARROW:-⇡}

	[[ -n $arrows ]] || return
	typeset -g REPLY=" $arrows"
}

prompt_pure_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4

	case $job in
		prompt_pure_async_git_status)
			local prev_status=$prompt_pure_git_status
			prompt_pure_git_status="$output"
			[ ! -z "$output" ] && prompt_pure_git_status+=" "

			[[ $prev_status != $prompt_pure_git_status ]] && prompt_pure_preprompt_render

			# When prompt_pure_git_last_status_check_timestamp is set, the git info is displayed in a different color.
			# To distinguish between a "fresh" and a "cached" result, the preprompt is rendered before setting this
			# variable. Thus, only upon next rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 2 )) && prompt_pure_git_last_status_check_timestamp=$EPOCHSECONDS
			;;
		prompt_pure_async_git_fetch|prompt_pure_async_git_arrows)
			# prompt_pure_async_git_fetch executes prompt_pure_async_git_arrows
			# after a successful fetch.
			if (( code == 0 )); then
				local REPLY
				prompt_pure_check_git_arrows ${(ps:\t:)output}
				if [[ $prompt_pure_git_arrows != $REPLY ]]; then
					prompt_pure_git_arrows=$REPLY
					prompt_pure_preprompt_render
				fi
			fi
			;;
	esac
}

prompt_pure_setup() {
	local autoload_name=$1; shift

	# prevent percentage showing up
	# if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	# if autoload_name or eval context differ, pure wasn't autoloaded via
	# promptinit and we need to take care of setting the options ourselves
	if [[ $autoload_name != prompt_pure_setup ]] || [[ $zsh_eval_context[-2] != loadautofunc ]]; then
		# borrowed from `promptinit`, set the pure prompt options
		setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	# vcs_info: http://zsh.sourceforge.net/Doc/Release/User-Contributions.html
	# TODO: replace vcs_info with $(zsh_prompt_info)
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# only export two msg variables from vcs_info
	zstyle ':vcs_info:*' max-exports 2
	# vcs_info_msg_0_ = ' %b' (for branch)
	# vcs_info_msg_1_ = 'x%R' git top level (%R), x-prefix prevents creation of a named path (AUTO_NAME_DIRS)
	zstyle ':vcs_info:git*' formats ':%b' 'x%R'
	zstyle ':vcs_info:git*' actionformats ':%b%F{yellow}:%a%f' 'x%R'

	# for git status
	# TODO: Remove dependency to prezto/git (but requires another one such as omz)
	zstyle ':prezto:module:git:info' verbose 'yes'
	zstyle ':prezto:module:git:info:action'    format ':%%B%F{yellow}%s%f%%b'
	zstyle ':prezto:module:git:info:added'     format ' %%B%F{green}✚%f%%b'
	#zstyle ':prezto:module:git:info:ahead'     format ' %%B%F{blue}↑%f%%b'
	#zstyle ':prezto:module:git:info:behind'    format ' %%B%F{blue}↓%f%%b'
	zstyle ':prezto:module:git:info:branch'    format ':%F{green}%b%f'
	zstyle ':prezto:module:git:info:commit'    format '(%F{yellow}%.7c%f)'
	zstyle ':prezto:module:git:info:deleted'   format ' %%B%F{red}✖%f%%b'
	zstyle ':prezto:module:git:info:modified'  format ' %%B%F{yellow}✱%f%%b'
	zstyle ':prezto:module:git:info:position'  format ':%F{red}%p%f'
	zstyle ':prezto:module:git:info:renamed'   format ' %%B%F{magenta}→%f%%b'
	zstyle ':prezto:module:git:info:stashed'   format ' %%B%F{cyan}✭%f%%b'
	zstyle ':prezto:module:git:info:unmerged'  format ' %%B%F{yellow}═%f%%b'
	zstyle ':prezto:module:git:info:untracked' format ' %%B%F{white}?%f%%b'

	zstyle ':prezto:module:git:info:keys' format \
		'prompt' ' $(coalesce "%b" "%c")%s' \
		'rprompt' '%S%a%d%m%r%U%u'
		#'rprompt' '%A%B%S%a%d%m%r%U%u'   # exclude ahead/behind

	# python virtualenv
	zstyle ':prezto:module:python:info:virtualenv' format ' %B%F{cyan}%v%f%b'

	# if the user has not registered a custom zle widget for clear-screen,
	# override the builtin one so that the preprompt is displayed correctly when
	# ^L is issued.
	if [[ $widgets[clear-screen] == 'builtin' ]]; then
		zle -N clear-screen prompt_pure_clear_screen
	fi

	# prompt with vi-keybindings -- https://github.com/sindresorhus/pure/wiki
	zstyle ':prezto:module:editor:info:keymap:primary' format '%B%F{red}❯%F{yellow}❯%(?.%F{green}.%F{red})❯%f%b'
	zstyle ':prezto:module:editor:info:keymap:alternate' format '%B%(?.%F{green}.%F{red})❮%F{yellow}❮%F{red}❮%f%b'

	# prompt turns red if the previous command didn't exit with 0
	PROMPT='%B%(?.%F{green}.%F{red})${editor_info[keymap]}%f%b '

	# sprompt
	SPROMPT='zsh: correct %F{red}%R%f to %F{green}%r%f [nyae]? '
}

prompt_pure_setup "$0" "$@"

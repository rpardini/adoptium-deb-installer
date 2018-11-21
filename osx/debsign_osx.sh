#! /bin/bash

# This program is designed to GPG sign a .dsc and .changes file pair
# in the form needed for a legal Debian upload.  It is based in part
# on dpkg-buildpackage.  It takes one argument: the name of the
# .changes file.

# Debian GNU/Linux debsign.  Copyright (C) 1999 Julian Gilbey.
# Modifications to work with GPG by Joseph Carter and Julian Gilbey
# Modifications for OS X command-line utils (C) 2013 Mikhail Gusarov
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# Abort if anything goes wrong
set -e

PRECIOUS_FILES=0
PROGNAME=`basename $0`
MODIFIED_CONF_MSG='Default settings modified by devscripts configuration files:'

# Temporary directories
signingdir=""
remotefilesdir=""

trap "cleanup_tmpdir" EXIT HUP INT QUIT KILL SEGV PIPE TERM

# --- Functions

mksigningdir () {
    if [ -z "$signingdir" ]; then
	signingdir="$(mktemp -dt debsign.XXXXXXXX)" || {
	    echo "$PROGNAME: Can't create temporary directory" >&2
	    echo "Aborting..." >&2
	    exit 1
	}
    fi
}

mkremotefilesdir () {
    if [ -z "$remotefilesdir" ]; then
	remotefilesdir="$(mktemp -dt debsign.XXXXXXXX)" || {
	    echo "$PROGNAME: Can't create temporary directory" >&2
	    echo "Aborting..." >&2
	    exit 1
	}
    fi
}

usage () {
    echo \
"Usage: debsign [options] [changes, dsc or commands file]
  Options:
    -r [username@]remotehost
                    The machine on which the changes/dsc files live.
                    A changes file with full pathname (or relative
                    to the remote home directory) must be given in
                    such a case
    -k<keyid>       The key to use for signing
    -p<sign-command>  The command to use for signing
    -e<maintainer>  Sign using key of <maintainer> (takes precedence over -m)
    -m<maintainer>  The same as -e
    -S              Use changes file made for source-only upload
    -a<arch>        Use changes file made for Debian target architecture <arch>
    -t<target>      Use changes file made for GNU target architecture <target>
    --multi         Use most recent multiarch .changes file found
    --re-sign       Re-sign if the file is already signed.
    --no-re-sign    Don't re-sign if the file is already signed.
    --debs-dir <directory>
                    The location of the .changes / .dsc files when called from
                    within a source tree (default "..")
    --no-conf, --noconf
                    Don't read devscripts config files;
                    must be the first option given
    --help          Show this message
    --version       Show version and copyright information
  If a commands or dsc or changes file is specified, it and any .dsc files in
  the changes file are signed, otherwise debian/changelog is parsed to find
  the changes file.

$MODIFIED_CONF_MSG"
}

version () {
    echo \
"This is debsign, from the Debian devscripts package, version 2.12.6
This code is copyright 1999 by Julian Gilbey, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}

temp_filename() {
    local filename

    if ! [ -w "$(dirname "$1")" ]; then
	filename=`mktemp -t "$(basename "$1").$2.XXXXXXXXXX"` || {
	    echo "$PROGNAME: Unable to create temporary file; aborting" >&2
	    exit 1
	}
    else
	filename="$1.$2"
    fi

    echo "$filename"
}

movefile() {
    if [ -w "$(dirname "$2")" ]; then
	mv -f -- "$1" "$2"
    else
	cat "$1" > "$2"
	rm -f "$1"
    fi
}

cleanup_tmpdir () {
    if [ -n "$remotefilesdir" ] && [ -d "$remotefilesdir" ]; then
	if [ "$PRECIOUS_FILES" -gt 0 ]; then
	    echo "$PROGNAME: aborting with $PRECIOUS_FILES signed files in $remotefilesdir" >&2
	    # Only produce the warning once...
	    PRECIOUS_FILES=0
	else
	    cd ..
	    rm -rf "$remotefilesdir"
	fi
    fi

    if [ -n "$signingdir" ] && [ -d "$signingdir" ]; then
	rm -rf "$signingdir"
    fi
}

mustsetvar () {
    if [ "x$2" = x ]
    then
	echo >&2 "$PROGNAME: unable to determine $3"
	exit 1
    else
	# echo "$PROGNAME: $3 is $2"
	eval "$1=\"\$2\""
    fi
}

# This takes two arguments: the name of the file to sign and the
# key or maintainer name to use.  NOTE: this usage differs from that
# of dpkg-buildpackage, because we do not know all of the necessary
# information when this function is read first.
signfile () {
    local savestty=$(stty -g 2>/dev/null) || true
    mksigningdir
    UNSIGNED_FILE="$signingdir/$(basename "$1")"
    ASCII_SIGNED_FILE="${UNSIGNED_FILE}.asc"
    (cat "$1" ; echo "") > "$UNSIGNED_FILE"

    gpgversion=`$signcommand --version | head -n 1 | cut -d' ' -f3`
    gpgmajorversion=`echo $gpgversion | cut -d. -f1`
    gpgminorversion=`echo $gpgversion | cut -d. -f2`

    if [ $gpgmajorversion -gt 1 -o $gpgminorversion -ge 4 ]
    then
	    $signcommand --local-user "$2" --clearsign \
		--list-options no-show-policy-urls \
		--armor --textmode --output "$ASCII_SIGNED_FILE"\
		"$UNSIGNED_FILE" || \
	    { SAVESTAT=$?
	      echo "$PROGNAME: $signcommand error occurred!  Aborting...." >&2
	      stty $savestty 2>/dev/null || true
	      exit $SAVESTAT
	    }
    else
	    $signcommand --local-user "$2" --clearsign \
		--no-show-policy-url \
		--armor --textmode --output "$ASCII_SIGNED_FILE" \
		"$UNSIGNED_FILE" || \
	    { SAVESTAT=$?
	      echo "$PROGNAME: $signcommand error occurred!  Aborting...." >&2
	      stty $savestty 2>/dev/null || true
	      exit $SAVESTAT
	    }
    fi
    stty $savestty 2>/dev/null || true
    echo
    PRECIOUS_FILES=$(($PRECIOUS_FILES + 1))
    movefile "$ASCII_SIGNED_FILE" "$1"
}

withecho () {
    echo " $@"
    "$@"
}

# Has the dsc file already been signed, perhaps from a previous, partially
# successful invocation of debsign?  We give the user the option of
# resigning the file or accepting it as is.  Returns success if already
# and failure if the file needs signing.  Parameters: $1=filename,
# $2=file description for message (dsc or changes)
check_already_signed () {
    [ "`head -n 1 \"$1\"`" = "-----BEGIN PGP SIGNED MESSAGE-----" ] || \
	return 1

    local resign
    if [ "$opt_re_sign" = "true" ]; then
	resign="true"
    elif [ "$opt_re_sign" = "false" ]; then
	resign="false"
    else
	response=n
	if [ -z "$DEBSIGN_ALWAYS_RESIGN" ]; then
	    printf "The .$2 file is already signed.\nWould you like to use the current signature? [Yn]"
	    read response
	fi
	case $response in
	[Nn]*) resign="true" ;;
	*)     resign="false" ;;
	esac
    fi

    [ "$resign" = "true" ] || \
	return 0

    UNSIGNED_FILE="$(temp_filename "$1" "unsigned")"

    sed -e '1,/^$/d; /^$/,$d' "$1" > "$UNSIGNED_FILE"
    movefile "$UNSIGNED_FILE" "$1"
    return 1
}

# --- main script

# Unset GREP_OPTIONS for sanity
unset GREP_OPTIONS

# Boilerplate: set config variables
DEFAULT_DEBSIGN_ALWAYS_RESIGN=
DEFAULT_DEBSIGN_PROGRAM=
DEFAULT_DEBSIGN_MAINT=
DEFAULT_DEBSIGN_KEYID=
DEFAULT_DEBRELEASE_DEBS_DIR=..
VARS="DEBSIGN_ALWAYS_RESIGN DEBSIGN_PROGRAM DEBSIGN_MAINT"
VARS="$VARS DEBSIGN_KEYID DEBRELEASE_DEBS_DIR"

if [ "$1" = "--no-conf" -o "$1" = "--noconf" ]; then
    shift
    MODIFIED_CONF_MSG="$MODIFIED_CONF_MSG
  (no configuration files read)"

    # set defaults
    for var in $VARS; do
	eval "$var=\$DEFAULT_$var"
    done
else
    # Run in a subshell for protection against accidental errors
    # in the config files
    eval $(
	set +e
	for var in $VARS; do
	    eval "$var=\$DEFAULT_$var"
	done

	for file in /etc/devscripts.conf ~/.devscripts
	  do
	  [ -r $file ] && . $file
	done

	set | egrep '^(DEBSIGN|DEBRELEASE|DEVSCRIPTS)_')

    # We do not replace this with a default directory to avoid accidentally
    # signing a broken package
    DEBRELEASE_DEBS_DIR="$(echo "${DEBRELEASE_DEBS_DIR%/}" | sed -e 's%/\+%/%g')"
    if ! [ -d "$DEBRELEASE_DEBS_DIR" ]; then
	debsdir_warning="config file specified DEBRELEASE_DEBS_DIR directory $DEBRELEASE_DEBS_DIR does not exist!"
    fi

    # set config message
    MODIFIED_CONF=''
    for var in $VARS; do
	eval "if [ \"\$$var\" != \"\$DEFAULT_$var\" ]; then
	    MODIFIED_CONF_MSG=\"\$MODIFIED_CONF_MSG
  $var=\$$var\";
	MODIFIED_CONF=yes;
	fi"
    done

    if [ -z "$MODIFIED_CONF" ]; then
	MODIFIED_CONF_MSG="$MODIFIED_CONF_MSG
  (none)"
    fi
fi

maint="$DEBSIGN_MAINT"
signkey="$DEBSIGN_KEYID"
debsdir="$DEBRELEASE_DEBS_DIR"

signcommand=''
if [ -n "$DEBSIGN_PROGRAM" ]; then
    signcommand="$DEBSIGN_PROGRAM"
else
    if command -v gpg > /dev/null 2>&1; then
	signcommand=gpg
    fi
fi

ggetopt="$(brew --prefix gnu-getopt)/bin/getopt"
TEMP=$($ggetopt -n "$PROGNAME" -o 'p:m:e:k:Sa:t:r:h' \
	      -l 'multi,re-sign,no-re-sign,debs-dir:' \
	      -l 'noconf,no-conf,help,version' \
	      -- "$@") || (rc=$?; usage >&2; exit $rc)

eval set -- "$TEMP"

#exit;

while true
do
    case "$1" in
	-p) signcommand="$2"; shift ;;
	-m) maint="$2"; shift ;;
	-e) maint="$2"; shift ;;
	-k) signkey="$2"; shift ;;
	-S) sourceonly="true" ;;
	-a) targetarch="$2"; shift ;;
	-t) targetgnusystem="$2"; shift ;;
	--multi) multiarch="true" ;;
	--re-sign)    opt_re_sign="true" ;;
	--no-re-sign) opt_re_sign="false" ;;
	-r)	remotehost=$2; shift
		# Allow for the [user@]host:filename format
		hostpart="${remotehost%:*}"
		filepart="${remotehost#*:}"
		if [ -n "$filepart" -a "$filepart" != "$remotehost" ]; then
		    remotehost="$hostpart"
		    set -- "$@" "$filepart"
		fi
		;;
	--debs-dir)
	    shift
	    opt_debsdir="$(echo "${1%/}" | sed -e 's%/\+%/%g')"
	    ;;
	--no-conf|--noconf)
		echo "$PROGNAME: $1 is only acceptable as the first command-line option!" >&2
		exit 1 ;;
	-h|--help)
		usage; exit 0 ;;
	--version)
		version; exit 0 ;;
	--)	shift; break ;;
    esac
    shift
done

debsdir=${opt_debsdir:-$debsdir}
# check sanity of debsdir
if ! [ -d "$debsdir" ]; then
    if [ -n "$debsdir_warning" ]; then
        echo "$PROGNAME: $debsdir_warning" >&2
        exit 1
    else
        echo "$PROGNAME: could not find directory $debsdir!" >&2
        exit 1
    fi
fi

if [ -z "$signcommand" ]; then
    echo "Could not find a signing program!" >&2
    exit 1
fi

dosigning() {
    # Do we have to download the changes file?
    if [ -n "$remotehost" ]
    then
	mkremotefilesdir
	cd "$remotefilesdir"

	remotechanges=$changes
	remotedsc=$dsc
	remotecommands=$commands
	remotedir="`perl -e 'chomp($_="'"$dsc"'"); m%/% && s%/[^/]*$%% && print'`"
	changes=`basename "$changes"`
	dsc=`basename "$dsc"`
	commands=`basename "$commands"`

	if [ -n "$changes" ]
	then
	    if [ ! -f "$changes" ]
	    then
		withecho scp "$remotehost:$remotechanges" .
	    fi
	elif [ -n "$dsc" ]
	then withecho scp "$remotehost:$remotedsc" "$dsc"
	else withecho scp "$remotehost:$remotecommands" "$commands"
	fi

	if [ -n "$changes" ] && echo "$changes" | egrep -q '[][*?]'
	then
	    for changes in $changes
	    do
		printf "\n"
		dsc=`echo "${remotedir+$remotedir/}$changes" | \
		    perl -pe 's/\.changes$/.dsc/; s/(.*)_(.*)_(.*)\.dsc/\1_\2.dsc/'`
		dosigning;
	    done
	    exit 0;
	fi
    fi

    if [ -n "$changes" ]
    then
	if [ ! -f "$changes" -o ! -r "$changes" ]
	then
	    echo "$PROGNAME: Can't find or can't read changes file $changes!" >&2
	    exit 1
	fi

	check_already_signed "$changes" "changes" && {
	   echo "Leaving current signature unchanged." >&2
	   return
	}
	if [ -n "$maint" ]
	then maintainer="$maint"
	# Try the "Changed-By:" field first
	else maintainer=`sed -n 's/^Changed-By: //p' $changes`
	fi
	if [ -z "$maintainer" ]
	then maintainer=`sed -n 's/^Maintainer: //p' $changes`
	fi

	signas="${signkey:-$maintainer}"

	# Is there a dsc file listed in the changes file?
	if grep -q `basename "$dsc"` "$changes"
	then
	    if [ -n "$remotehost" ]
	    then
		withecho scp "$remotehost:$remotedsc" "$dsc"
	    fi

	    if [ ! -f "$dsc" -o ! -r "$dsc" ]
	    then
		echo "$PROGNAME: Can't find or can't read dsc file $dsc!" >&2
		exit 1
	    fi
	    check_already_signed "$dsc" "dsc" || withecho signfile "$dsc" "$signas"
	    dsc_md5=`md5 $dsc | cut -d' ' -f4`
	    dsc_sha1=`shasum -a1 $dsc | cut -d' ' -f1`
	    dsc_sha256=`shasum -a256 $dsc | cut -d' ' -f1`

	    temp_changes="$(temp_filename "$changes" "temp")"
	    cp "$changes" "$temp_changes"
	    if perl -i -pe 'BEGIN {
		'" \$dsc_file=\"$dsc\"; \$dsc_md5=\"$dsc_md5\"; "'
		'" \$dsc_sha1=\"$dsc_sha1\"; \$dsc_sha256=\"$dsc_sha256\"; "'
		$dsc_size=(-s $dsc_file); ($dsc_base=$dsc_file) =~ s|.*/||;
		$infiles=0; $insha1=0; $insha256=0; $format="";
		}
		if(/^Format:\s+(.*)/) {
		    $format=$1;
		    die "Unrecognised .changes format: $format\n"
			unless $format =~ /^\d+(\.\d+)*$/;
		    ($major, $minor) = split(/\./, $format);
		    $major+=0;$minor+=0;
		    die "Unsupported .changes format: $format\n"
			if($major!=1 or $minor > 8 or $minor < 7);
		}
		/^Files:/i && ($infiles=1,$insha1=0,$insha256=0);
		if(/^Checksums-Sha1:/i) {$insha1=1;$infiles=0;$insha256=0;}
		elsif(/^Checksums-Sha256:/i) {
		    $insha256=1;$infiles=0;$insha1=0;
		} elsif(/^Checksums-.*?:/i) {
		    die "Unknown checksum format: $_\n";
		}
		/^\s*$/ && ($infiles=0,$insha1=0,$insha256=0);
		if ($infiles &&
		    /^ (\S+) (\d+) (\S+) (\S+) \Q$dsc_base\E\s*$/) {
		    $_ = " $dsc_md5 $dsc_size $3 $4 $dsc_base\n";
		    $infiles=0;
		}
		if ($insha1 &&
		    /^ (\S+) (\d+) \Q$dsc_base\E\s*$/) {
		    $_ = " $dsc_sha1 $dsc_size $dsc_base\n";
		    $insha1=0;
		}
		if ($insha256 &&
		    /^ (\S+) (\d+) \Q$dsc_base\E\s*$/) {
		    $_ = " $dsc_sha256 $dsc_size $dsc_base\n";
		    $insha256=0;
		}' "$temp_changes"
	    then
		movefile "$temp_changes" "$changes"
	    else
		rm "$temp_changes"
		echo "$PROGNAME: Error processing .changes file (see above)" >&2
		exit 1
	    fi

	    withecho signfile "$changes" "$signas"

	    if [ -n "$remotehost" ]
	    then
		withecho scp "$changes" "$dsc" "$remotehost:$remotedir"
		PRECIOUS_FILES=$(($PRECIOUS_FILES - 2))
	    fi

	    echo "Successfully signed dsc and changes files"
	else
	    withecho signfile "$changes" "$signas"

	    if [ -n "$remotehost" ]
	    then
		withecho scp "$changes" "$remotehost:$remotedir"
		PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
	    fi

	    echo "Successfully signed changes file"
	fi
    elif [ -n "$commands" ] # sign .commands file
    then
	if [ ! -f "$commands" -o ! -r "$commands" ]
	then
	    echo "$PROGNAME: Can't find or can't read commands file $commands!" >&2
	    exit 1
	fi

	check_already_signed "$commands" commands && {
	    echo "Leaving current signature unchanged." >&2
	    return
	}

	# simple validator for .commands files, see
	# ftp://ftp.upload.debian.org/pub/UploadQueue/README
	perl -ne 'BEGIN { $uploader = 0; $incommands = 0; }
              END { exit $? if $?;
                    if ($uploader && $incommands) { exit 0; }
                    else { die ".commands file missing Uploader or Commands field\n"; }
                  }
              sub checkcommands {
                  chomp($line=$_[0]);
                  if ($line =~ m%^\s*reschedule\s+[^\s/]+\.changes\s+[0-9]+-day\s*$%) { return 0; }
                  if ($line =~ m%^\s*cancel\s+[^\s/]+\.changes\s*$%) { return 0; }
                  if ($line =~ m%^\s*rm(\s+(?:DELAYED/[0-9]+-day/)?[^\s/]+)+\s*$%) { return 0; }
                  if ($line eq "") { return 0; }
                  die ".commands file has invalid Commands line: $line\n";
              }
              if (/^Uploader:/) {
                  if ($uploader) { die ".commands file has too many Uploader fields!\n"; }
                  $uploader++;
              } elsif (! $incommands && s/^Commands:\s*//) {
                  $incommands=1; checkcommands($_);
              } elsif ($incommands == 1) {
                 if (s/^\s+//) { checkcommands($_); }
                 elsif (/./) { die ".commands file: extra stuff after Commands field!\n"; }
                 else { $incommands = 2; }
              } else {
                 next if /^\s*$/;
                 if (/./) { die ".commands file: extra stuff after Commands field!\n"; }
              }' $commands || {
	echo "$PROGNAME: .commands file appears to be invalid. see:
ftp://ftp.upload.debian.org/pub/UploadQueue/README
for valid format" >&2;
	exit 1; }

	if [ -n "$maint" ]
	then maintainer="$maint"
	else
            maintainer=`sed -n 's/^Uploader: //p' $commands`
            if [ -z "$maintainer" ]
            then
		echo "Unable to parse Uploader, .commands file invalid."
		exit 1
            fi
	fi

	signas="${signkey:-$maintainer}"

	withecho signfile "$commands" "$signas"

	if [ -n "$remotehost" ]
	then
	    withecho scp "$commands" "$remotehost:$remotecommands"
	    PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
	fi

	echo "Successfully signed commands file"
    else # only a dsc file to sign; much easier
	if [ ! -f "$dsc" -o ! -r "$dsc" ]
	then
	    echo "$PROGNAME: Can't find or can't read dsc file $dsc!" >&2
	    exit 1
	fi

	check_already_signed "$dsc" dsc && {
	    echo "Leaving current signature unchanged." >&2
	    return
	}
	if [ -n "$maint" ]
	then maintainer="$maint"
	# Try the new "Changed-By:" field first
	else maintainer=`sed -n 's/^Changed-By: //p' $dsc`
	fi
	if [ -z "$maint" ]
	then maintainer=`sed -n 's/^Maintainer: //p' $dsc`
	 fi

	signas="${signkey:-$maintainer}"

	withecho signfile "$dsc" "$signas"

	if [ -n "$remotehost" ]
	then
	    withecho scp "$dsc" "$remotehost:$remotedsc"
	    PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
	fi

	echo "Successfully signed dsc file"
    fi
}

# If there is a command-line parameter, it is the name of a .changes file
# If not, we must be at the top level of a source tree and will figure
# out its name from debian/changelog
case $# in
    0)	# We have to parse debian/changelog to find the current version
	if [ -n "$remotehost" ]; then
	    echo "$PROGNAME: Need to specify a .changes, .dsc or .commands file location with -r!" >&2
	    exit 1
	fi
	if [ ! -r debian/changelog ]; then
	    echo "$PROGNAME: Must be run from top of source dir or a .changes file given as arg" >&2
	    exit 1
	fi

	mustsetvar package "`dpkg-parsechangelog | sed -n 's/^Source: //p'`" \
	    "source package"
	mustsetvar version "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" \
	    "source version"

	if [ "x$sourceonly" = x ]
	then
	    mustsetvar arch "`dpkg-architecture -a${targetarch} -t${targetgnusystem} -qDEB_HOST_ARCH`" "build architecture"
	else
	    arch=source
	fi

	sversion=`echo "$version" | perl -pe 's/^\d+://'`
	pv="${package}_${sversion}"
	pva="${package}_${sversion}_${arch}"
	dsc="$debsdir/$pv.dsc"
	changes="$debsdir/$pva.changes"
	if [ -n "$multiarch" -o ! -r $changes ]; then
	    changes=$(ls "$debsdir/${package}_${sversion}_*+*.changes" "$debsdir/${package}_${sversion}_multi.changes" 2>/dev/null | head -1)
	    if [ -z "$multiarch" ]; then
		if [ -n "$changes" ]; then
		    echo "$PROGNAME: could not find normal .changes file but found multiarch file:" >&2
		    echo "  $changes" >&2
		    echo "Using this changes file instead." >&2
		else
		    echo "$PROGNAME: Can't find or can't read changes file $changes!" >&2
		    exit 1
		fi
	    elif [ -n "$multiarch" -a -z "$changes" ]; then
		echo "$PROGNAME: could not find any multiarch .changes file with name" >&2
		echo "$debsdir/${package}_${sversion}_*.changes" >&2
		exit 1
	    fi
	fi
	dosigning;
	;;

    *)	while [ $# -gt 0 ]; do
	    case "$1" in
		*.dsc)
		    changes=
		    dsc=$1
		    commands=
		    ;;
	        *.changes)
		    changes=$1
		    dsc=`echo $changes | \
			perl -pe 's/\.changes$/.dsc/; s/(.*)_(.*)_(.*)\.dsc/\1_\2.dsc/'`
		    commands=
		    ;;
		*.commands)
		    changes=
		    dsc=
		    commands=$1
		    ;;
		*)
		    echo "$PROGNAME: Only a .changes, .dsc or .commands file is allowed as argument!" >&2
		    exit 1 ;;
	    esac
	    dosigning
	    shift
	done
	;;
esac

exit 0

#!/bin/bash -ue
#
#  bysykkelstatus fetches and parses city bike rack data for Oslo, Norway
#  Shell scripting for teh win!
#  Copyright (C) 2010 Christian Bryn <chr.bryn@gmail.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

config_file_path=~/.bysykkelrc

# remote services
racks_url="http://smartbikeportal.clearchannel.no/public/mobapp/maq.asmx/getRacks"
rack_url="http://smartbikeportal.clearchannel.no/public/mobapp/maq.asmx/getRack?id="

# Define our schema/'DTD' :-)
#
# tags: ready_bikes empty_locks online description longitute latitude
tags="ready_bikes empty_locks online description longitute latitude"

ready_bikes="n/a"


# Parse xml to tag/value pairs - tags are $E, values are $C
# ex:
#    while rdom; do
#            if [[ $E = title ]]; then
#                echo $C
#                exit
#            fi
#    done < xhtmlfile.xhtml    # < <( echo "$result" )
#

rdom () { local IFS=\> ; read -d \< E C ;}

function valid_id {
    # valid IDs are numbers only, max 3
    if ( echo "${1}" | grep -q "[^0-9]" || [ "$( echo -ne "${1}" | wc -m )" -gt 3 ] ); 
        then return 1
        else return 0
    fi
}

function list_rack_ids {
    local tags="station"
    result=$( wget -q "$racks_url" -O - | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' )

    stations=""
    for tag in $tags;
    do
        while rdom; do
            if [[ $E = "$tag" ]]; then
                stations="$stations $C"
            fi
        done < <( echo $result )
    done
    echo -en "${stations}"
}



function print_usage {
    cat <<EOF
Query Oslo Bysykkel racks for current status - any available bikes for me plz?
Defaults to printing rack id and available bikes.
Usage: ${0} [-a|-c <config file>|-f <favourites>|-h|-l|-r <rack id>]
    -a      Print all info from rack
    -c      Define config file to read from (defaults to ~/.bysykkelrc)
    -f      Define favourites (ids) and write config file. Combine with -c to specify output path.
    -h      I'm helpful.
    -l      Query for and return available rack id's, then exit (not very useful).
    -r      Rack ID to query for - this can also be set in the favourites file. Use keyword "all" to list all racks.

Examples:
    ${0} -a -r 75
    ${0} -r "75 77 37"
    ${0} -r all
    ${0} -f 75
    ${0} -f "75 24"
EOF
}

rack_ids=""
print_all="false"
html="false"
favourites=""
# read favorites
test -f "${config_file_path}" && source "${config_file_path}"
if [ "${favourites}" != "" ]; then
    rack_ids="${favourites}"
fi
while getopts ac:f:Hhlr: o
do
    case $o in
        h)
            print_usage
            exit
            ;;
        a)
            print_all="true"
            ;;
        c)
            config_file_path="${OPTARG}"
            ;;
        f)
            favourites="${OPTARG}"
            # todo: validate input here
            printf "# space separated list of favourites\nfavourites=\'${favourites}\'\n" > "${config_file_path}" || { echo "[ error ] Could not write to ${config_file_path}"; exit 1; } 
            exit 0;
            ;;
        H)
            html="true"
            ;;
        l)
            echo $( list_rack_ids )
            exit 0;
            ;;
        r)
            rack_ids="${OPTARG}"
            if [ "${rack_ids}" == "all" ]; then
                rack_ids="$( list_rack_ids )"
            else
                for rack_id in $rack_ids; do
                    valid_id "${rack_id}" || { echo "error: $rack_id is not a valid rack id! List available racks with -l"; exit 1; }
                done
            fi
            ;;
        
        *)
            print_usage
            exit 1
            ;;
    esac
done
shift $(($OPTIND-1))

[ "$html" == "true" ] && \
    echo '<html><head>
<title>Bysykkelstatus</title>

<style tupe="text/css">
    body { font-family: verdana,sans; font-size: 8pt; }
    td { font-family: verdana, sans; font-size: 10pt; }
</style>
</head>
<body>
<table>'


for rack_id in $rack_ids;
do
    # fetch data for given rack and convert html-code tags to normal tagz
    result=$( wget -q "${rack_url}${rack_id}" -O - | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' ) || { echo "Could not fetch data!"; exit 1; }

    # parse xml from result and store as variables
    # read from file descriptor rather than pipe to 'while read' in order to avoid subshell and thus be able to store variables in our current shell
    for tag in $tags;
    do
        while rdom; do
            if [[ $E = "$tag" ]]; then
                eval ${tag}=$( echo -ne \""$C"\" )
            fi
        done < <( echo $result )
    done

    if [ "${print_all}" == "true" ]; then
        # tag that bitch
        for tag in $tags; do
            echo $tag $( eval echo "\$$tag" )
        done
    else
        if [ "$html" == "true" ];
        then printf "<tr><td>%s</td><td>%d</td></tr>\n" "$description" "$ready_bikes"
        else printf "%-5d %-90s %s\n" "${ready_bikes}" "${description}"
        fi
    fi
done

[ "$html" == "true" ] && \
    echo -ne "</table>\n generated $( date ) \n</body></html>\n"

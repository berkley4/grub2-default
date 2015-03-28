#!/bin/sh
#set -e

i=0; x=0; y=0

if [ "$USER" != "root" ]; then
  echo "run this script as root, eg su -c \"$0\""
  exit 1
fi

if [ "$(grep '/boot' /etc/fstab)" ]; then
  if [ "$(grep '/boot' /etc/mtab)" ]; then
    if [ "$(grep -E '/boot [a-z]+[0-9]? ro,' /etc/mtab)" ]; then
      mount -o rw,remount /boot
    fi
  else
    mount -o rw /boot
  fi
fi

config_file="$(find /boot/grub* -maxdepth 1 -name grub.cfg 2>/dev/null)"
if [ -z $config_file ]; then
  echo "ERROR: cannot find grub.cfg in /boot/grub or /boot/grub2"
  exit 1
fi

default_file="$(find /etc/default \( -name grub -o -name grub2 \) 2>/dev/null)"
if [ -z $default_file ]; then
  echo "ERROR: cannot find grub or grub2 file in /etc/default"
  exit 1
fi

for g in update-grub update-grub2; do
  command -v $g >/dev/null
  [ $? -eq 1 ] || { UPDATE_GRUB=$g; break; }
done

if [ -z $UPDATE_GRUB ]; then
  echo "ERROR: cannot execute update-grub or update-grub2"
  echo "check that grub is installed"
  exit 1
fi



menu_raw="$(grep -E '(submenu |menuentry )' $config_file | \
            sed 's@\([^'\"\'']*\)['\"\'']\([^'\"\'']*\)['\"\''].*@\1\2@')"

menu_max=$(expr $(echo "$menu_raw" | grep -v '^[[:space:]]' | wc -l) - 1)

menu_list="$(echo "$menu_raw" | \
             while IFS= read line
             do
               if [ "$(echo "$line" | grep '^[[:space:]]')" ]
               then
                 echo "$line"
               else
                 sp=""
                 [ $menu_max -lt 10 ] || sp=" "
                 [ $i -lt 10 ] || sp=""
                 echo "$i/$sp$line"
                 i=$(expr $i + 1)
               fi
             done | sed -e 's@submenu@@' -e 's@menuentry@@'
           )"

mlist() { echo "$menu_list"; }



echo "\n\n<<<<< MENU >>>>>\n"
echo "$menu_list\n"
echo -n "Enter menu number [0-$menu_max] (q=exit) > "
read menu_number

case $menu_number in
  [0-9]|[0-9][0-9])
    if [ $menu_number -gt $menu_max ]; then
      echo "ERROR: invalid menu number"
      exit 1
    fi ;;

  q|Q)
    exit 0 ;;

  *)
    echo "ERROR: invalid input"
    exit 1 ;;
esac

selected_menu="$(mlist | grep ^$menu_number | sed 's@[^"]*\(".*\)@\1@')"



if [ -z "$(mlist | grep -A1 "$selected_menu" | grep '^[[:space:]]')" ]
then
  default_menu=$menu_number
else
  selected_title="$(echo "$selected_menu" | sed 's@^[0-9][^/]*/[ ]*@@')"

  sub_max=$(expr $(echo "$menu_raw" | grep ^[[:space:]] | wc -l) - 1)

  sub_list="$(echo "$menu_raw" | \
              while IFS= read line
              do
                if [ $x -gt $menu_number ]
                then
                  if [ "$(echo "$line" | grep -E '^(submenu |menuentry )')" ]
                  then
                    break
                  else
                    sp=""
                    [ $sub_max -lt 10 ] || sp=" "
                    [ $y -lt 10 ] || sp=""
                    echo "$line" | sed "s@.*menuentry@$y/$sp@"
                    y=$(expr $y + 1)
                  fi
                fi
                x=$(expr $x + 1)
              done
            )"

  echo "\n\n\n<<<<< $selected_title >>>>>\n"
  echo "$sub_list\n"
  echo -n "Enter submenu number [0-$sub_max] (q=exit) > "
  read sub_number

  case $sub_number in
    [0-9]|[0-9][0-9])
      if [ $sub_number -gt $sub_max ]; then
        echo "ERROR: invalid submenu number"
        exit 1
      fi
      default_menu="$menu_number>$sub_number"
      selected_sub="$(echo "$sub_list" | grep ^$sub_number/ | \
                      sed 's@[^"]*\(".*\)@\1@')" ;;

    q|Q)
      exit 0 ;;

    *)
      echo "ERROR: invalid input"
      exit 1 ;;
  esac
fi


echo "\n\n\nMENU:    $selected_menu"
[ -z "$selected_sub" ] || echo "SUBMENU: $selected_sub"
echo "\nSetting GRUB_DEFAULT=\"$default_menu\" in $default_file\n\n"

cp -a $default_file $default_file.bak
sed "s@^\(GRUB_DEFAULT=\).*@\1\"$default_menu\"@" \
    <$default_file.bak > $default_file

exec $UPDATE_GRUB


exit 0

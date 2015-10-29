#!/bin/sh
#set -e

i=0; j=0; FOUND=0; END=0

[ "$USER" = "root" ] || { echo "run this script as root"; exit 1; }

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
[ $config_file ] || { echo "ERROR: cannot find grub.cfg file"; exit 1; }

deflt_file="$(find /etc/default \( -name grub -o -name grub2 \) 2>/dev/null)"
[ $deflt_file ] || { echo "ERROR: cannot find default grub file"; exit 1; }

for g in update-grub update-grub2; do
  command -v $g >/dev/null
  [ $? -eq 1 ] || { UPDATE_GRUB=$g; break; }
done
[ $UPDATE_GRUB ] || { echo "ERROR: update-grub is not working"; exit 1; }



menu_raw="$(grep -E '(submenu |menuentry )' $config_file | \
            sed 's@\([^'\"\'']*\)['\"\'']\([^'\"\'']*\)['\"\''].*@\1\2@')"

menu_list="$(echo "$menu_raw" | \
             while IFS= read line; do
               if [ "$(echo "$line" | grep ^[[:space:]])" ]
               then
                 echo "$line"
               else
                 sp=" "
                 [ $i -lt 10 ] || sp=""
                 echo "$i/  $sp$line"
                 i=$(expr $i + 1)
               fi
             done | sed -e 's@submenu@@' -e 's@menuentry@@')"

menu_max=$(expr $(echo "$menu_list" | grep ^[0-9] | wc -l) - 1)


echo "\n\n<<<<< MENU >>>>>\n"
echo "$menu_list\n"
echo -n "Enter menu number [0-$menu_max] (q=exit) > "; read menu_num

case $menu_num in
  [0-9]|[0-9][0-9])
    [ $menu_num -le $menu_max ] || { echo "invalid number"; exit 1; } ;;

  q|Q)
    exit 0 ;;

  *)
    echo "invalid input"
    exit 1 ;;
esac

chosen_menu="$(echo "$menu_list" | grep ^$menu_num/ | sed 's@[^"]*\(".*\)@\1@')"
next_item="$(echo "$menu_list" | grep -A1 "$chosen_menu" | tail -n1)"


if [ "$(echo "$next_item" | grep ^[0-9][^/]*/)" ]
then
  default_menu=$menu_num
else
  chosen_title="$(echo "$chosen_menu" | sed 's@^[0-9][^/]*/[ ]*@@')"

  sub_list="$(echo "$menu_list" | \
              while IFS= read line; do
                [ -z "$(echo "$line" | grep "$next_item")" ] || FOUND=1
                if [ $FOUND -eq 1 ]; then
                  [ -z "$(echo "$line" | grep ^[0-9])" ] || END=1
                fi
                if [ $FOUND -eq 1 ] && [ $END -eq 0 ]; then
                  sp=" "
                  [ $j -lt 10 ] || sp=""
                  echo "$j/  $sp$(echo "$line" | sed 's@^[ \t]*\(.*\)@\1@')"
                  j=$(expr $j + 1)
                fi
              done)"

  sub_max=$(expr $(echo "$sub_list" | wc -l) - 1)


  echo "\n\n\n<<<<< $chosen_title >>>>>\n"
  echo "$sub_list\n"
  echo -n "Enter submenu number [0-$sub_max] (q=exit) > "; read sub_num

  case $sub_num in
    [0-9]|[0-9][0-9])
      [ $sub_num -le $sub_max ] || { echo "invalid number"; exit 1; }
      default_menu="$menu_num>$sub_num"
      chosen_sub="$(echo "$sub_list" | grep ^$sub_num/ | \
                    sed 's@[^"]*\(".*\)@\1@')" ;;

    q|Q)
      exit 0 ;;

    *)
      echo "invalid input"
      exit 1 ;;
  esac
fi


echo "\n\n\nMENU:    $chosen_menu"
[ -z "$chosen_sub" ] || echo "SUBMENU: $chosen_sub"
echo "\nSetting GRUB_DEFAULT=\"$default_menu\" in $deflt_file\n\n"

cp -a $deflt_file $deflt_file.bak
sed "s@^\(GRUB_DEFAULT=\).*@\1\"$default_menu\"@" <$deflt_file.bak >$deflt_file

exec $UPDATE_GRUB


exit 0

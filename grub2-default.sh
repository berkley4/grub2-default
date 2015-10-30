#!/bin/sh
#set -e

x=0; y=0; B=0

[ "$USER" = "root" ] || { echo "run this script as root"; exit 1; }

if [ "$(grep '/boot' /etc/fstab)" ]; then
  if [ "$(grep '/boot' /etc/mtab)" ]; then
    if [ "$(sed -n '/\/boot [a-z0-9][a-z0-9]* ro,/p' /etc/mtab)" ]; then
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



menu_list="$(sed -n -e 's@\([^'\"\'']*\)['\"\'']\([^'\"\'']*\).*@\1\2@' \
                    -e '/\(submenu\|menuentry\) /p' <$config_file | \
               while IFS= read ln
               do
                 if [ "$(echo "$ln" | grep ^[[:space:]])" ]
                 then
                   echo "$ln"
                 else
                   sp=" "
                   [ $x -lt 10 ] || sp=""

                   echo "$x/  $sp$ln"

                   x=$(expr $x + 1)
                 fi
               done | sed 's@\(submenu\|menuentry\) @@')"

menu_max=$(expr $(echo "$menu_list" | grep ^[0-9] | wc -l) - 1)


echo "\n\n$menu_list\n"
echo -n "Enter menu number [0-$menu_max] (q=exit) > "; read menu_num

case $menu_num in
  [0-9]|[0-9][0-9])
    [ $menu_num -le $menu_max ] || { echo "invalid number"; exit 1; }
    chosen_menu="$(echo "$menu_list" | grep ^$menu_num/)"
    next_item="$(echo "$menu_list" | grep -A1 ^$menu_num/ | tail -n1)" ;;

  q|Q)
    exit 0 ;;

  *)
    echo "invalid input"
    exit 1 ;;
esac


if [ "$(echo "$next_item" | grep ^[0-9][^/]*/)" ]
then
  default_menu=$menu_num
else
  chosen_title="$(echo "$chosen_menu" | sed 's@^[^/]*/[ ]*@@')"

  sub_list="$(echo "$menu_list" | \
                while IFS= read ln
                do
                  [ -z "$(echo "$ln" | grep "$next_item")" ] || B=1

                  [ $B -eq 0 ] || [ -z "$(echo "$ln" | grep ^[0-9])" ] || break

                  if [ $B -eq 1 ]; then
                    sp=" "
                    [ $y -lt 10 ] || sp=""

                    echo "    $y)$sp $(echo "$ln" | sed 's@^[ \t]*@@')"

                    y=$(expr $y + 1)
                  fi
                done)"

  sub_max=$(expr $(echo "$sub_list" | wc -l) - 1)


  echo "\n\n\n$(echo "$chosen_menu" | sed 's@\(^[^/]*/\)[ \t]*@\1  @')  >>>\n"
  echo "$sub_list\n"
  echo -n "Enter submenu number [0-$sub_max] (q=exit) > "; read sub_num

  case $sub_num in
    [0-9]|[0-9][0-9])
      [ $sub_num -le $sub_max ] || { echo "invalid number"; exit 1; }
      default_menu="$menu_num>$sub_num"
      chosen_sub="$(echo "$sub_list" | grep ^$sub_num/)" ;;

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

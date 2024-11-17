#!/bin/sh

#
# Copyright (c) 2022, Clockwork
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# VERSION 0.0.1

# Define colors
color_off="\033[m"
color_red="\033[1;31m"
color_green="\033[1;32m"
color_yellow="\033[1;33m"
color_grey="\033[1;30m"
color_blue="\033[1;34m"
color_teal="\033[1;36m"
color_purple="\033[1;35m"

h_flag=false

for arg in "$@"; do
  if [ "$arg" = "-h" ]; then
    h_flag=true
  fi
done

if [ "$h_flag" = true ]; then
  printf "Syntax:\n	-h 	help
	-b	bar
	-bb	bar-info
	-d	disk
	-e	net
	-p	proc
	-g	gpu (nvidia)\n"
  exit 0
fi

# Определение размера страницы
hw_pagesize=$(sysctl -n hw.pagesize)

# Получаем количество неактивной памяти
mem_inactive=$(( $(sysctl -n vm.stats.vm.v_inactive_count) * hw_pagesize ))

# Получаем количество неиспользуемой памяти
mem_unused=$(( $(sysctl -n vm.stats.vm.v_free_count) * hw_pagesize ))

# Получаем количество кэшированной памяти
mem_cache=$(( $(sysctl -n vm.stats.vm.v_cache_count) * hw_pagesize ))

# Получаем количество активной памяти
mem_active=$(( $(sysctl -n vm.stats.vm.v_active_count) * hw_pagesize ))

# Получаем количество wired (закрепленной) памяти
mem_wired=$(( $(sysctl -n vm.stats.vm.v_wire_count) * hw_pagesize ))

# Получаем количество `laundry` памяти
mem_laundry=$(( $(sysctl -n vm.stats.vm.v_laundry_count) * hw_pagesize ))

# Получаем количество буферной памяти
mem_buf=$(( $(sysctl -n vfs.bufspace) / 1024 / 1024 ))

# Получаем количество зарезервированной памяти
mem_reserved=$(( $(sysctl -n vm.stats.vm.v_free_reserved) * hw_pagesize ))

# Вычисляем общий объем памяти
mem_total=$(( $(sysctl -n hw.physmem) / 1024 / 1024 ))

# Получаем количество страниц в транзите
mem_intrans=$(( $(sysctl -n vm.stats.vm.v_intrans) * hw_pagesize ))

v_flag=false

for arg in "$@"; do
  if [ "$arg" = "-v" ]; then
    v_flag=true
  fi
done

if [ "$v_flag" = true ]; then
  # Проверка транзитных страниц
  if [ "$(( $mem_intrans / 1024 / 1024 ))" -gt "$mem_total" ]; then
    echo -e "${color_red}[Critical]${color_off}: mem_intrans ($mem_intrans) превышает mem_total!"
    uptime=$(LANG=en_US.UTF-8 uptime | sed -n 's/.*up \([^,]*\),.*/\1/p')
    echo "	UPTIME: ${uptime}"
  #else
  #  echo -e "${color_green}[Ok]${color_off}: Транзитные страницы в норме."
  fi
  
  swap=$(swapinfo -m)
  if echo "$swap" | grep -q "Total"; then
    usage=$(echo "$swap" | awk '/Total/{print $5}' | sed 's/%//')
    if [ "$usage" -gt 60 ]; then
      echo -e "${color_red}[Warning]${color_off}: Swap used: ($usage%)."
    else
      echo -e "${color_green}[Ok]${color_off}: Swap used: ($usage%)"
    fi
  elif echo "$swap" | grep -q '^\/' ; then
    usage=$(echo "$swap" | awk '/^\//{print $5}' | sed 's/%//')
    if [ "$usage" -gt 60 ]; then
      echo -e "${color_red}[Warning]${color_off}: Swap used: ($usage%)."
    else
      echo -e "${color_green}[Ok]${color_off}: Swap used: ($usage%)"
    fi
  else
      echo -e "${color_green}[Ok]${color_off}: Нету свопа"
  fi

########################
# Получаем список всех tmpfs
  tmpfs_list=$(mount | grep tmpfs | awk '{print $3}')

# Переменная для флага состояния tmpfs
  tmpfs_is_bad=false

# Проверка на наличие tmpfs
  if [ -n "$tmpfs_list" ]; then
    # Проверка использования tmpfs
    for mount_point in $tmpfs_list; do
      df -h | grep "$mount_point" | awk '{print $5}' | sed 's/%//' | while read usage; do
  #      echo "usage: ${usage}"
        if [ "$usage" -gt 80 ]; then
          echo "[Warning]: tmpfs is bad - $mount_point usage: $usage%"
          tmpfs_is_bad=true
        fi
      done
    done
  
    # Проверка состояния tmpfs
    if [ "$tmpfs_is_bad" = false ]; then
      echo -e "${color_green}[Ok]${color_off}: tmpfs в пределах нормы"
    fi
  else
    echo -e "${color_green}[Ok]${color_off}: tmpfs не используется"
  fi

####################################
# Проверка наличия md устройств
  md_list=$(ls /dev/md[0-9]* 2>/dev/null)

# Если md устройства не найдены, выводим сообщение и выходим
  if [ -z "$md_list" ]; then
    echo -e "${color_green}[Ok]${color_off}: md's не используются"
  else
    # Переменная для хранения общей суммы
    total_md_mem=0
    threshold=80  # Порог в процентах
  
    # Проверка каждого md устройства
    for md in $md_list; do
      # Получаем номер md устройства
      md_unit=$(echo $md | grep -o '[0-9]*')
      # Получаем размер md устройства в КБ и преобразуем в МБ
      md_size_kb=$(sudo mdconfig -l -u $md_unit | awk '{print $3}' | sed 's/K//')
      md_size_mb=$((md_size_kb / 1024))
      
      # Добавляем размер к общей сумме
      total_md_mem=$((total_md_mem + md_size_mb))
    done
  
    # Проверка загруженности md устройств
    if [ "$total_md_mem" -gt "$threshold" ]; then
      echo -e "${color_red}[Warning]${color_off}: /dev/md* $total_md_mem MiB (превышен порог в 80 MiB)"
    else
      echo -e "${color_green}[Ok]${color_off}: /dev/md* $total_md_mem MiB (в пределах нормы)"
    fi
  fi
###############################
# Проверка значения vm.stats.vm.v_vm_faults
  vm_faults=$(sysctl -n vm.stats.vm.v_vm_faults)
  if [ "$vm_faults" -gt 5000000 ]; then
    echo -e "${color_red}[Critical]${color_off}: Проблема с виртуальной памятью, vm_faults: $vm_faults"
  fi
  
  total_swap=$(swapinfo -m | awk '/^\/dev/ {total += $2} END {print total * 1024 * 1024}')  # перевод в байты
  
  # Проверка фрагментации свопа
  min_free_size=$((total_swap / 10))  # 10% от общего объема свопа

#v_flag=false
#
#for arg in "$@"; do
#  if [ "$arg" = "-v" ]; then
#    v_flag=true
#  fi
#done

#if [ "$v_flag" = true ]; then
    sysctl vm.swap_fragmentation | grep -E 'Free space on device|number of maximal free ranges:|largest free range:|average maximal free range size:' | \
    while read -r line; do
        case "$line" in
            *"Free space on device"*) device=$(echo "$line" | awk '{print $5}' | tr -d ':') ;;
            *"number of maximal free ranges:"*) ranges=$(echo "$line" | awk '{print $6}') ;;
            *"largest free range:"*) largest=$(echo "$line" | awk '{print $4}') ;;
            *"average maximal free range size:"*) average=$(echo "$line" | awk '{print $6}')
                # Проверяем условия
                # Вывод значений для отладки
    #            echo "Debug: device='$device', ranges='$ranges', largest='$largest', average='$average'"
    
                # Проверка на пустоту и на числовое значение
                if [ -z "$largest" ] || ! echo "$largest" | grep -qE '^[0-9]+$'; then
                    echo "[error]: некорректное значение для largest: '$largest'"
                    continue
                fi
                
                if [ -z "$average" ] || ! echo "$average" | grep -qE '^[0-9]+$'; then
                    echo "[error]: некорректное значение для average: '$average'"
                    continue
                fi
    
                # Проверяем условия
                [ "$ranges" -gt 5 ] && echo -e "${color_red}[Warning]${color_off}: Фрагментация свопа на устройстве $device: Количество диапазонов ($ranges) превышает 5"
    	    # Это указывает на избыточную фрагментацию. Средняя.
                [ "$largest" -lt "$min_free_size" ] && echo -e "${color_red}[Warning]${color_off}: Фрагментация свопа на устройстве $device: Наибольший свободный диапазон ($largest) меньше $min_free_size"
    	    # Говорит о том, что свободное пространство не подходит для эффективного использования. Критическая.
                [ "$average" -lt "$min_free_size" ] && echo -e "${color_red}[Warning]${color_off}: Фрагментация свопа на устройстве $device: Средний размер свободного диапазона ($average) меньше $min_free_size"
    	    # Дополнительно подтверждает наличие фрагментации. Критическая.
                ;;
        esac
    done
  # Нет прямого лечения на FreeBSD от фрагментации свопа. Решение:
  # 1) Устранить проблему активного использования свопа.
  # 2) Пересоздать разделы, используемые для свопа:
  # swapoff /dev/ada0p3 
  # swapoff /dev/ada1p3
  # gpart delete -i <номер> ada0
  # gpart create -s GPT ada0
  # gpart add -t freebsd-swap -l swap0 ada0
  # swapon /dev/ada0p3

  # Проверка общего объема оперативной памяти
  total_mem=$(sysctl -n hw.physmem)
  total_mem_gb=$((total_mem / 1024 / 1024 / 1024))
  # Установка флага в зависимости от объема оперативной памяти
  if [ "$total_mem_gb" -gt 8 ]; then
    mem_flag="8mem"
  else
    mem_flag="no8mem"
  fi

  swap_reserved=$(sysctl -n vm.swap_reserved)
  if [ "$mem_flag" = "8mem" ]; then
    critical_reserved_threshold=$((total_mem * 30 / 100))  # 30% от объема оперативной памяти
  else
    critical_reserved_threshold=$((total_mem * 20 / 100))  # 20% от объема оперативной памяти
  fi

  porog=$(( $critical_reserved_threshold / 1024 / 1024 ))
  wreser=$(( $swap_reserved / 1024 / 1024 ))
  if [ "$swap_reserved" -gt "$critical_reserved_threshold" ]; then
	  echo -e "${color_red}[Warning]${color_off}: swap_reserved: $swap_reserved ($wreser Mib) превышает критический порог $porog Mib"
  fi

  zfs_count=$(df -T | awk 'BEGIN{n=0};{if($2=="zfs"){n++}};END{print n}')
  if [ "$zfs_count" -ne 0 ]; then
    # Проверка copy-on-write faults 
    cow_faults=$(vmstat -s | grep 'copy-on-write faults' | awk '{print $1}')
    if [ "$cow_faults" -gt 5000000 ]; then
      echo -e "${color_red}[Warning]${color_off}: Чрезмерное использование механизма COW на высоких нагрузках $cow_faults"
    fi
    
    # Проверка значения vm.stats.vm.v_io_faults
    io_faults=$(sysctl -n vm.stats.vm.v_io_faults)
    if [ "$io_faults" -gt 500000 ]; then
      echo -e "${color_red}[Warning]${color_off}: Проблемы с вводом-выводом, io_faults: $io_faults"
    fi
    
    # Проверка значения vm.stats.vm.v_cow_faults
    cow_faults=$(sysctl -n vm.stats.vm.v_cow_faults)
    if [ "$cow_faults" -gt 2000000000 ]; then
      echo -e "${color_red}[Warning]${color_off}: Чрезмерное использование механизма COW, cow_faults: $cow_faults"
    fi
  fi


###############################
  today=$(LANG=en_US.UTF-8 date '+%b %e')

# Проверка логов за сегодняшний день на наличие OOM killer событий
  log_file="/var/log/messages"
  oom_killed=$(grep -i "oom\|kill" "$log_file" | grep "$today")

# Если найдено хотя бы одно событие, выводим сообщение
  if [ -n "$oom_killed" ]; then
    count=$(echo "$oom_killed" | wc -l)
    echo -e "${color_red}[Warning]${color_off}: OOM kill: $count today."
  #  echo "Список:"
  #  echo "$oom_killed" | while read -r line; do
  #    echo "$(echo "$line" | awk -F: '{print $4}')"
  #  done
  #else
  #  echo "Сегодня не было событий OOM Killer."
  fi

# Проверка логов на наличие сообщений о нехватке swap-памяти
  swap_errors=$(grep -i "swap_pager: out of swap space\|swp_pager_getswapspace" "$log_file" | grep "$today")
# Если найдены сообщения о нехватке swap-памяти, выводим предупреждение
  if [ -n "$swap_errors" ]; then
    last_error_time=$(echo "$swap_errors" | tail -n 1 | awk '{print $1, $2, $3}')
    echo -e "${color_red}[Critical]${color_off}: Swap переполнен. Last msg: $last_error_time."
  fi

echo ""
fi

# Вычисляем общее количество использованной памяти
mem_used=$(( (mem_active + mem_inactive + mem_unused + mem_cache + mem_wired + mem_laundry + mem_buf + mem_reserved + mem_intrans) / 1024 / 1024 ))

# Расчет процента использования памяти
mem_used_percentage=$(( mem_used * 100 / mem_total ))

# Вывод информации о памяти
#echo "All: ${mem_used}MiB / ${mem_total}MiB (${mem_used_percentage}%)"

mem_free="$(((mem_inactive + mem_unused + mem_cache) / 1024 / 1024))"
mem_free_percentage=$(( 100 - mem_free * 100 / mem_total))

echo -e "${color_green}[meminfo]${color_off}: Memory: $(( ${mem_total} - ${mem_free} )) Mib / ${mem_total} Mib (${mem_free_percentage}%)"
#printf "Active: ${mem_active},\nWired: ${mem_wired},\nLaundry: ${mem_laundry},\nBuf: ${mem_buf},\nReserved: ${mem_reserved},\nIntrans: ${mem_intrans}\n\n"
#printf "Inact: ${mem_inactive}\nUnused: ${mem_unused}\nCache: ${mem_cache}\n"
#echo ""

################################
proc_wired=$(( mem_wired * 100 / mem_total ))
proc_active=$(( mem_active * 100 / mem_total ))
proc_laundary=$(( mem_laundry * 100 / mem_total ))
proc_buf=$(( mem_buf * 100 / mem_total ))
proc_reserved=$(( mem_reserved * 100 / mem_total ))
proc_intrans=$(( mem_intrans * 100 / mem_total ))
proc_free=$(( mem_free * 100 ))

proc_w=$(( mem_wired / 1024 / 1024 )) 
proc_a=$(( mem_active / 1024 / 1024 )) 
proc_l=$(( mem_laundry / 1024 / 1024 )) 
proc_b=$(( mem_buf / 1024 / 1024 )) 
proc_r=$(( mem_reserved / 1024 / 1024 )) 
proc_i=$(( mem_intrans / 1024 / 1024 )) 

bar_length=75
total_proc=$(( proc_w + proc_a + proc_l + proc_b + proc_r + proc_i + mem_free ))

wired_length=$(( proc_w * bar_length / total_proc ))
active_length=$(( proc_a * bar_length / total_proc ))
laundary_length=$(( proc_l * bar_length / total_proc ))
buf_length=$(( proc_b * bar_length / total_proc ))
reserved_length=$(( proc_r * bar_length / total_proc ))
intrans_length=$(( proc_i * bar_length / total_proc ))
free_length=$(( mem_free * bar_length / total_proc ))

red_bar=$(printf "%0.s|" $(seq 1 $wired_length))
green_bar=$(printf "%0.s|" $(seq 1 $active_length))
yellow_bar=$(printf "%0.s|" $(seq 1 $laundary_length))
blue_bar=$(printf "%0.s|" $(seq 1 $buf_length))
teal_bar=$(printf "%0.s|" $(seq 1 $reserved_length))
purple_bar=$(printf "%0.s|" $(seq 1 $intrans_length))
grey_bar=$(printf "%0.s|" $(seq 1 $free_length))

echo -e "[${color_red}${red_bar}${color_green}${green_bar}${color_yellow}${yellow_bar}${color_blue}${blue_bar}${color_teal}${teal_bar}${color_purple}${purple_bar}${color_grey}${grey_bar}${color_off}]"

bb_flag=false

for arg in "$@"; do
  if [ "$arg" = "-bb" ]; then
    bb_flag=true
  fi
done

if [ "$bb_flag" = true ]; then
  printf "Wired: $(( $mem_wired / 1024 / 1024 )) Mib ${color_red}|${color_off}, Active: $(( $mem_active / 1024 / 1024 )) Mib ${color_green}|${color_off}, \nLaundary: $(( ${mem_laundry} / 1024 / 1024 )) Mib ${color_yellow}|${color_off}, Buf: $(( ${mem_buf} / 1024 / 1024 )) Mib ${color_blue}|${color_off}, \nReserved: $(( ${mem_reserved} / 1024 / 1024 )) Mib ${color_teal}|${color_off}, Intrans: $(( ${mem_intrans} / 1024 / 1024 )) Mib ${color_purple}|${color_off}, \nFree: ${mem_free} Mib ${color_grey}|${color_off}\n\n"
else
  printf "\n"
fi

################################
#rss=$(

p_flag=false

for arg in "$@"; do
  if [ "$arg" = "-p" ]; then
    p_flag=true
  fi
done

if [ "$p_flag" = true ]; then
#  top -b  | awk '
#function parse_memory(mem) {
#    unit = substr(mem, length(mem), 1)
#    value = substr(mem, 1, length(mem)-1)
#    if (unit == "M") {
#        return value * 1024
#    } else if (unit == "K") {
#        return value
#    } else {
#        return value / 1024 # На случай, если единицы измерения не указаны
#    }
#}
#NR > 7 {
#    if ($7 ~ /^[0-9]+[a-zA-Z]+$/) {
#        mem = $7
#        process_name = $12  # Имя процесса (последняя колонка)
#        mem_value = parse_memory(mem)
#        rss_sum_kb += mem_value
#        print "Processed:", mem, "=", mem_value, "KB", process_name  # Отладочное сообщение с именем процесса
#    }
#}
#END {
#    print "Total RSS Sum:", rss_sum_kb / 1024, "MiB"
#}'
top -b -o res | awk '
function parse_memory(mem) {
    unit = substr(mem, length(mem), 1)
    value = substr(mem, 1, length(mem)-1)
    if (unit == "M") {
        return value * 1024
    } else if (unit == "K") {
        return value
    } else {
        return value / 1024 # На случай, если единицы измерения не указаны
    }
}
NR > 7 {
    if ($7 ~ /^[0-9]+[a-zA-Z]+$/) {
        mem = $7
        process_name = $12  # Имя процесса (последняя колонка)
        mem_value = parse_memory(mem)
        rss_sum_kb += mem_value
        print "Processed:", mem, "=", mem_value, "KB", process_name  # Отладочное сообщение с именем процесса
    }
}
END {
    print "Total RES Sum:", rss_sum_kb / 1024, "MiB"
}' #Для большей точности сортировка по res
chrom=$(ps -auxww | grep "chrom" | grep -v 'grep' | sort -nrk 4 | awk '{print $4 "%", $11}' | wc -l)
echo -e "\nпроцессов chrome: ${chrom}"
firefox=$(ps -auxww | grep "firefox" | grep -v 'grep' | sort -nrk 4 | awk '{print $4 "%", $11}' | wc -l)
echo -e "процессов firefox: ${firefox}\n"
else
#  top -b -o res | awk '
#function parse_memory(mem) {
#    unit = substr(mem, length(mem), 1)
#    value = substr(mem, 1, length(mem)-1)
#    if (unit == "M") {
#        return value * 1024
#    } else if (unit == "K") {
#        return value
#    } else {
#        return value / 1024 # На случай, если единицы измерения не указаны
#    }
#}
#NR > 7 {
#    if ($7 ~ /^[0-9]+[a-zA-Z]+$/) {
#        mem = $7
#        process_name = $12  # Имя процесса (последняя колонка)
#        mem_value = parse_memory(mem)
#        rss_sum_kb += mem_value
##        print "Processed:", mem, "=", mem_value, "KB", process_name  # Отладочное сообщение с именем процесса
#    }
#}
#END {
#    print "Total RES Sum:", rss_sum_kb / 1024, "MiB"
#}'
top -b -o res | awk -v mem_total="$mem_total" '
function parse_memory(mem) {
    unit = substr(mem, length(mem), 1)
    value = substr(mem, 1, length(mem)-1)
    if (unit == "M") {
        return value * 1024
    } else if (unit == "K") {
        return value
    } else {
        return value / 1024  # На случай, если единицы измерения не указаны
    }
}
NR > 7 {
    if ($7 ~ /^[0-9]+[a-zA-Z]+$/) {
        mem = $7
        process_name = $12  # Имя процесса (последняя колонка)
        mem_value = parse_memory(mem)
        rss_sum_kb += mem_value
#        print "Processed:", mem, "=", mem_value, "KB", process_name  # Отладочное сообщение с именем процесса
    }
}
END {
    rss_sum_mib = rss_sum_kb / 1024
    usage_percentage = (rss_sum_mib / mem_total) * 100
    printf "Total RES Sum: %.0f MiB (%.2f%%)\n", rss_sum_mib, usage_percentage
}'
#)
#top -b -o size | awk '
#function parse_memory(mem) {
#    unit = substr(mem, length(mem), 1)
#    value = substr(mem, 1, length(mem)-1)
#    if (unit == "G") {
#        return value * 1024 * 1024  # Конвертация гигабайт в килобайты
#    } else if (unit == "M") {
#        return value * 1024  # Конвертация мегабайтов в килобайты
#    } else if (unit == "K") {
#        return value  # Килобайты остаются без изменений
#    } else {
#        return value * 1024 * 1024  # На случай, если единицы измерения не указаны, предполагаем гигабайты
#    }
#}
#NR > 7 {
#    if ($6 ~ /^[0-9]+[a-zA-Z]+$/) {
#        mem = $6
#        process_name = $12  # Имя процесса (последняя колонка)
#        mem_value = parse_memory(mem)
#        size_sum_kb += mem_value
##        print "Processed:", mem, "=", mem_value, "KB", process_name  # Отладочное сообщение с именем процесса
#    }
#}
#END {
#    print "Total SIZE Sum:", size_sum_kb / (1024 * 1024), "GiB"
#}'
top -b -o size | awk -v mem_total="$mem_total" '
function parse_memory(mem) {
    unit = substr(mem, length(mem), 1)
    value = substr(mem, 1, length(mem)-1)
    if (unit == "G") {
        return value * 1024 * 1024  # Конвертация гигабайт в килобайты
    } else if (unit == "M") {
        return value * 1024  # Конвертация мегабайтов в килобайты
    } else if (unit == "K") {
        return value  # Килобайты остаются без изменений
    } else {
        return value * 1024 * 1024  # На случай, если единицы измерения не указаны, предполагаем гигабайты
    }
}
NR > 7 {
    if ($6 ~ /^[0-9]+[a-zA-Z]+$/) {
        mem = $6
        process_name = $12  # Имя процесса (последняя колонка)
        mem_value = parse_memory(mem)
        size_sum_kb += mem_value
#        print "Processed:", mem, "=", mem_value, "KB", process_name  # Отладочное сообщение с именем процесса
    }
}
END {
    size_sum_gib = size_sum_kb / (1024 * 1024)
    usage_percentage = (size_sum_gib * 1024 / mem_total) * 100
    printf "Total SIZE Sum: %.0f GiB (%.2f%%)\n", size_sum_gib, usage_percentage
}'
# VIRT включает в себя:
#    Фактически используемую оперативную память (RES).
#    Память, выделенную, но не используемую.
#    Память, выделенную для общего использования (shared memory).
#    Память, которая может быть сброшена или пересчитана.
#    Память, которая подлежит свопу.
fi

b_flag=false

for arg in "$@"; do
  if [ "$arg" = "-b" ]; then
    b_flag=true
  fi
done

if [ "$b_flag" = true ]; then
  rss_total=$(top -b | awk 'function p(m) {u=substr(m,length(m),1);v=substr(m,1,length(m)-1);return u=="M"?v*1024:(u=="K"?v:v/1024)} NR>7 && $7 ~ /^[0-9]+[a-zA-Z]+$/ {rss+=p($7)} END {print int(rss/1024 + 0.5)}')
  bar_length=75
  meme_free=$(( mem_total - rss_total ))
  rss_length=$(( rss_total * bar_length / mem_total ))
  free__length=$(( meme_free * bar_length / mem_total ))
  rss_bar=$(printf "%0.s|" $(seq 1 $rss_length))
  free__bar=$(printf "%0.s|" $(seq 1 $free__length))
  echo -e "[${color_red}${rss_bar}${color_green}${color_grey}${free__bar}${color_off}]\n"
fi

#######################
# GPU



# Получение данных о видеопамяти
## Проверка существования команды nvidia-smi
#if ! command -v nvidia-smi > /dev/null 2>&1; then
#    echo "Команда nvidia-smi не найдена. Продолжаем выполнение."
#    # Если команда не найдена, ничего не делаем и продолжаем скрипт
#else
#    nvidia_smi_output=$(nvidia-smi -q)
#
#    # Извлечение информации из вывода nvidia-smi
#    total_gpu_memory=$(echo "$nvidia_smi_output" | grep -A3 "FB Memory Usage" | grep "Total" | awk '{print $3}')
#    used_gpu_memory=$(echo "$nvidia_smi_output" | grep -A3 "FB Memory Usage" | grep "Used" | awk '{print $3}')
#
#    # Парсинг значений видеопамяти
#    total_gpu_memory_kb=$(echo "$total_gpu_memory" | sed 's/[^0-9]*//g')000
#    used_gpu_memory_kb=$(echo "$used_gpu_memory" | sed 's/[^0-9]*//g')000
#
#    # Вычисление процентного использования
#    gpu_memory_percentage=$(awk "BEGIN {printf \"%.2f\", (${used_gpu_memory_kb}/${total_gpu_memory_kb})*100}")
#
#    # Вывод информации о видеопамяти
#    echo "Nvidia Memory Usage: $(($used_gpu_memory_kb / 1024)) MiB / $(($total_gpu_memory_kb / 1024)) MiB (${gpu_memory_percentage}%)"
#fi

# Проверка существования команды nvidia-smi
if command -v nvidia-smi > /dev/null 2>&1; then
    parse_memory() {
        mem=$1
        unit=$(echo ${mem} | sed 's/[0-9]*//g')
        value=$(echo ${mem} | sed 's/[^0-9]*//g')
        if [ "$unit" = "G" ]; then
            echo $(($value * 1024 * 1024)) # Конвертация гигабайт в килобайты
        elif [ "$unit" = "M" ]; then
            echo $(($value * 1024)) # Конвертация мегабайтов в килобайты
        elif [ "$unit" = "K" ]; then
            echo $value # Килобайты остаются без изменений
        else
            echo $(($value * 1024 * 1024)) # Предполагаем гигабайты, если единицы измерения не указаны
        fi
    }
    nvidia_smi_output=$(nvidia-smi -q)

    # Извлечение информации из вывода nvidia-smi
    total_gpu_memory=$(echo "$nvidia_smi_output" | grep -A3 "FB Memory Usage" | grep "Total" | awk '{print $3}')
    used_gpu_memory=$(echo "$nvidia_smi_output" | grep -A3 "FB Memory Usage" | grep "Used" | awk '{print $3}')

    # Парсинг значений видеопамяти
    total_gpu_memory_kb=$(echo "$total_gpu_memory" | sed 's/[^0-9]*//g')000
    used_gpu_memory_kb=$(echo "$used_gpu_memory" | sed 's/[^0-9]*//g')000

    # Вычисление процентного использования
    gpu_memory_percentage=$(awk "BEGIN {printf \"%.2f\", (${used_gpu_memory_kb}/${total_gpu_memory_kb})*100}")

    # Вывод информации о видеопамяти
    echo "Nvidia Memory Usage: $(($used_gpu_memory_kb / 1024)) MiB / $(($total_gpu_memory_kb / 1024)) MiB (${gpu_memory_percentage}%)"
#else
#    echo "Команда nvidia-smi не найдена. Продолжаем выполнение."
    # Если команда не найдена, ничего не делаем и продолжаем скрипт
fi


g_flag=false

for arg in "$@"; do
  if [ "$arg" = "-g" ]; then
    g_flag=true
  fi
done

if [ "$g_flag" = true ]; then
  if command -v nvidia-smi > /dev/null 2>&1; then
    nvidia=$(nvidia-smi -q | grep -E "Process ID|Used GPU Memory|Name" | sed -e 's/^[ \t]*//' | grep '^Used GPU Memory\|^Name');
    echo ""
    printf "${nvidia}" | awk 'NR%2{printf "%s ", substr($0, index($0, $3))} !(NR%2){print $5, $6}'
    echo ""
  else
    echo "Команда nvidia-smi не найдена. Продолжаем выполнение."
  fi
fi

#######################
# Если ZFS, то проверяем ARC:

#zfs_count=$(df -hT | awk '{if($2=="zfs"){print $1}}' | wc -l)
#zfs_count=$(df -T | awk 'BEGIN{n=0};{if($2=="zfs"){n++}};END{print n}')
if [ "$zfs_count" -ne 0 ]; then
    # Основной код для обработки ARC памяти
    mem_arc=$(sysctl -n kstat.zfs.misc.arcstats.size)
    mem_arc_mib=$((mem_arc / 1024 / 1024))  # делим на 1024 дважды

    # Получаем значение arc_max
    arc_max=$(sysctl -n vfs.zfs.arc_max)
    arc_max_auto=$(sysctl kstat.zfs.misc.arcstats.c_max | awk '{print int($2 / (1024 * 1024))}')

    # Проверка значения arc_max
    if [ "$arc_max" -eq 0 ]; then
        arc_total="auto (${arc_max_auto} MiB)"
        arc_max_mib=$arc_max_auto
    else
        arc_max_mib=$((arc_max / 1024 / 1024))  # переводим из байт в MiB
        arc_total="${arc_max_mib} MiB"
    fi

    # Вычисление процента использования
    arc_usage_percentage=$(awk "BEGIN {printf \"%.2f\", (${mem_arc_mib}/${arc_max_mib})*100}")

    # Вывод значения arc_total с процентом
    echo "ARC Memory Usage: ${mem_arc_mib} MiB / ${arc_total} (${arc_usage_percentage}%)"
#else
#    echo "[ok]: ARC не найден."
    # Если ZFS не найден, ничего не делаем и продолжаем скрипт
fi

#mem_arc=$(sysctl -n kstat.zfs.misc.arcstats.size)
#mem_arc_mib=$((mem_arc / 1024 / 1024))  # делим на 1024 дважды
#
## Получаем значение arc_max
#arc_max=$(sysctl -n vfs.zfs.arc_max)
#
#arc_max_auto=$(sysctl kstat.zfs.misc.arcstats.c_max | awk '{print int($2 / (1024 * 1024))" Mib"}')
##arc_max_auto=$(sysctl kstat.zfs.misc.arcstats.c_max | awk '{print int($2 / (1024 * 1024))}')
#
## Проверка значения arc_max
#if [ "$arc_max" -eq 0 ]; then
#  arc_total="auto ($arc_max_auto)"
#  arc_max_mib=$arc_max_auto
#else
#  arc_total=$( echo $((arc_max / 1024 / 1024)) Mib)  # переводим из байт в MiB
#  arc_total="${arc_max_mib} MiB"
#fi
#
## Вывод значения arc_total
##echo "ARC Memory Usage: ${mem_arc_mib} MiB / ${arc_total}"
#
## Вычисление процента использования
#arc_usage_percentage=$(awk "BEGIN {printf \"%.2f\", (${mem_arc_mib}/${arc_max_mib})*100}")
#
## Вывод значения arc_total с процентом
#echo "ARC Memory Usage: ${mem_arc_mib} MiB / ${arc_total} (${arc_usage_percentage}%)"


##Преимущества автоматического управления (vfs.zfs.arc_max=0):
# - Динамическое регулирование: Система автоматически подстраивает размер ARC в зависимости от текущей нагрузки и потребностей.
# - Оптимизация производительности: В условиях переменной нагрузки система может использовать больше или меньше памяти для ARC, обеспечивая оптимальную производительность.
# - Упрощение администрирования: Отпадает необходимость вручную настраивать параметры памяти и отслеживать их соответствие текущим условиям.
##Недостатки автоматического управления:
# - Непредсказуемость: Автоматическая настройка может привести к тому, что в некоторых ситуациях ARC будет занимать больше памяти, чем желательно, оставляя меньше памяти для других задач.
# - Временные задержки: Иногда автоматическое регулирование может занять время, что может привести к временным задержкам в производительности системы.

##Установка значения вручную (например, половина объема ОЗУ):
# - Контроль: Вы точно знаете, сколько памяти выделено для ARC, и можете управлять этим.
# - Стабильность: Фиксированное значение уменьшает вероятность непредсказуемых изменений, что может быть важно для критичных систем.
# - Оптимизация под конкретные задачи: Можно настроить размер ARC в зависимости от специфики задач, выполняемых на сервере.
##Недостатки ручной настройки:
# - Необходимость мониторинга: Параметры могут потребовать корректировки при изменении условий работы системы.
# - Потенциальная неэффективность: Фиксированное значение может быть либо избыточным, либо недостаточным в зависимости от текущей нагрузки.

#По дефолту 0
# sudo sysctl vfs.zfs.arc_max=0
# vfs.zfs.arc_max: 0
# sudo sysctl vfs.zfs.arc_max=$((16 * 1024 * 1024 * 1024))

#######################

# Проверка аргументов на наличие '-d'
run=false
for arg in "$@"; do
  if [ "$arg" = "-d" ]; then
    run=true
    break
  fi
done

if [ "$run" = true ]; then
  # Получаем список всех устройств ada
  ada_devices=$(gpart show | grep '^=>' | awk '/ada/{print $4}')

  # Если найдены устройства ada
  if [ -n "$ada_devices" ]; then
    for ada_device in $ada_devices; do
      smart_output=$(sudo smartctl -A /dev/$ada_device)
      critical_values="1 5 195 199 231"  # Только те ID, которые имеют отношение к памяти
      printf "\n"
      echo "Проверка устройства: $ada_device"

      for id in $critical_values; do
        value=$(echo "$smart_output" | awk -v id="$id" '$1 == id {print $10}')
        name=$(echo "$smart_output" | awk -v id="$id" '$1 == id {print $2}')

        if [ -n "$value" ]; then
          case $id in
            1)
              threshold=50
              ;;
            5)
              threshold=5
              ;;
            195)
              threshold=10000
              ;;
            199)
              threshold=50
              ;;
            231)
              threshold=10  # Задайте порог для SSD Life Left
              ;;
          esac

          if [ "$id" = "231" ]; then
            # Проверка для SSD_Life_Left
            if [ "$value" -lt "$threshold" ]; then
              echo -e "${color_red}[Warning]${color_off}: $name ($id) value is below the threshold ($threshold)! ${color_red}$value${color_off}"
            fi
          else
            # Проверка для остальных
            if [ "$value" -ge "$threshold" ]; then
              echo -e "${color_red}[Warning]${color_off}: $name ($id) value exceeds the threshold ($threshold)! ${color_red}$value${color_off}"
            fi
          fi
        fi
      done
    done
  else
    echo "[Ok]: No ada devices found"
  fi
fi

##############################

e_flag=false

for arg in "$@"; do
  if [ "$arg" = "-e" ]; then
    e_flag=true
  fi
done

if [ "$e_flag" = true ]; then
  printf "\nПроверка соединений...\n"
  # Получаем список установленных соединений, которые влияют на использование памяти.
  addresses=$(netstat -an | grep -E 'LISTEN|SYN_SENT|SYN_RECV|FIN_WAIT|TIME_WAIT|CLOSE_WAIT|LAST_ACK|ESTABLISHED' | awk '{print $5}' | grep -v '*.*')
  # Проходим по каждому адресу и выполняем команду lsof
  for addr in $addresses; do
#    echo "Проверка соединения: $addr"
    sudo lsof -i -P | grep "$addr" | awk '{print $1,$2,$8,$9,$10}'
  done
fi




#!/bin/bash
run_path=$(pwd)

nonusm_programmed=0
usm_programmed=0

exec < compile_testing_results.csv
read header

# Create new .csv file for run job as well
run_results_csv="${run_path}/full_testing_results.csv"
touch ${run_results_csv}

echo $header > ${run_results_csv}

while IFS=, read -r col1 col2 col3 col4 col5 col6
do
  cd ${run_path}
  if [[ $col3 == *"_usm"* ]]; then 
    if [ $usm_programmed == 0 ]; then 
      echo "________________________________________________________________________"
      echo "Programming usm .aocx!"
      aocl program acl0 usmbsp.aocx
      usm_programmed=$((usm_programmed+1))
    fi
  else
    if [ $nonusm_programmed == 0 ]; then 
      echo "________________________________________________________________________"
      echo "Programming non-usm .aocx!"
      aocl program acl0 non-usmbsp.aocx
      nonusm_programmed=$((nonusm_programmed+1))
    fi
  fi
  
  if [[ "${col5}" == "No" ]]; then
    echo "________________________________________________________________________"
    echo "Not running ${col1} design to hardware"
    echo "$col1,$col2,$col3,$col4,$col5,No-run" >> ${run_results_csv}
  else
    echo "________________________________________________________________________"
    echo "Running ${col1} design in hardware"
    cd ${run_path}/${col1}/${col3}

    if [[ ${col2} == "printf.fpga" ]]; then
      if ./${col2} | grep -q 'ABCD'; then
        echo "$col1,$col2,$col3,$col4,$col5,Passed" >> ${run_results_csv}
      else
        echo "$col1,$col2,$col3,$col4,$col5,Failed" >> ${run_results_csv}
      fi

    elif [[ ${col2} == "gzip.fpga" ]]; then
      dd if=/dev/zero of=./150M.txt bs=150M count=1 > /dev/null 2>&1
      dd if=/dev/zero of=./50K.txt bs=50K count=1 > /dev/null 2>&1

      if ./${col2} ./150M.txt -o=./150M.gz | grep -q 'PASSED' && ./${col2} ./50K.txt -o=./50K.gz | grep -q 'PASSED'; then
        echo "$col1,$col2,$col3,$col4,$col5,Passed" >> ${run_results_csv}
      else
        echo "$col1,$col2,$col3,$col4,$col5,Failed" >> ${run_results_csv}
      fi

    elif [[ ${col2} == "db.fpga" ]]; then
      cd ../data/sf1
      if ../../db.fpga | grep -q 'PASSED'; then
        echo "$col1,$col2,$col3,$col4,$col5,Passed" >> ${run_results_csv}
      else
        echo "$col1,$col2,$col3,$col4,$col5,Failed" >> ${run_results_csv}
      fi

    elif [[ ${col2} == "crr.fpga" ]]; then
      if ./${col2} | grep -q 'PASS'; then
        echo "$col1,$col2,$col3,$col4,$col5,Passed" >> ${run_results_csv}
      else
        echo "$col1,$col2,$col3,$col4,$col5,Failed" >> ${run_results_csv}
      fi

    else
      if ./${col2} | grep -q 'PASSED'; then
        echo "$col1,$col2,$col3,$col4,$col5,Passed" >> ${run_results_csv}
      else
        echo "$col1,$col2,$col3,$col4,$col5,Failed" >> ${run_results_csv}
      fi
    fi

  fi
done

# rm ${run_path}/compile_testing_results.csv

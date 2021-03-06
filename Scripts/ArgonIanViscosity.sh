#!/bin/bash
####
#
#This code submits a set of CH3 and CH2 parameter sets (determined by Bayesian MCMC with a different code)
#Simulations are performed at 5 conditions read from files.
#Temperatures are performed sequentially, batches of NREPS parameter sets are submitted at a time
#Green-Kubo analysis is used after each temperature loop is completed
#
#
####

### IN ORDER TO CALCULATE RDF FUNCTIONS:
# The groups specified by refs and sels (see below)
# must be specified in the original compound's .gro file
# Check that the names given in the .gro file are the names
# which actually appear in the index file if there are problems.
# Trajectory files must exists for the NVT production run
###

### IN ORDER TO RUN NEMD
# 
###

# Gives a more informative error when something goes wrong
# with the script.
error_report() {
echo "Error $1 on j $2, iMCMC $3, stage $4"
exit 1
}

clean() {   # Make it so everything is killed on an interrupt
local pids=$(jobs -pr)
echo "On exit sending kill signal to: $pids"
[ -n "$pids" ] && kill $pids
exit 1
}
trap "clean" SIGINT SIGTERM EXIT SIGQUIT  # Call cleanup when asked to

job_date=$(date "+%Y_%m_%d_%H_%M_%S")

Compound=Argon
Model=Ian_UD
Conditions_type=Argon    #Saturation         #"$Model"_Saturation   #Saturation # ie T293highP
BondType=LINCS  #Harmonic (flexible) or LINCS (fixed)
Temp=143.5  # Default temp, used if no temperature file is found in conditions path
jlim=1  # Upper bound on j; condition sets to run; exclusive. Should usually be 5
jlow=0 # Lower bound on j; inclusive. needed in special cases. Should usually be 0
batches=1  # Number of batches to run
NREPS=1 #Run NREPS replicates in parallel/# in a batch (Overriden by NEMD=YES)
pin0=0  # Default pinoffset, used to tell taskset where to run jobs
nt_eq=1  # Thread number during equilibration
nt_vis=1  # This thread number will serve in production and viscosity runs
NPT=NO # YES indicates NPT runs should be carried out prior to NVT runs (YES or NO)
#echo "CHANGE THIS BACK BEFORE RUNNING MORE T293highP!!!"
NEMD=NO  # Calculate viscosity using the periodic perturbation method  (YES or NO)
RDF=NO  # Whether to perform RDF calculations (YES or NO)
MCMC_tors=NO # YES indicates model includes torsional uncertainties
#Set the number of molecules
Nmol=1600
NREP_low=0 #Change this if starting batch from non-zero REP, only for a single j


###### STEP SIZE INFORMATION #######
# Runtiming control: override default runtimes=YES, otherwise use NO
OVERRIDE_STEPS=YES
# If OVERRIDE_STEPS=YES, arrays must be of length j 
# indicating how many equilibration and production steps,
# respectively, to perform for each j
equil_steps=(500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000)
prod_steps=(500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000 500000)
output_freq=(3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3)

# The mdp path is decided later based on the kind of run, but in the case that Lennard Jones
# mdp's will be used, the lj_mdp_path will be the variable selected, otherwise t_mdp_path will be used.
lj_mdp_path=~/LennardJones
t_mdp_path=~/Tabulated

#### RDF INFORMATION #####
RDF_single=NO   # Only perform one RDF run for each j (YES or NO)
rdfs=2  # Number of RDF functions to produce for each NVT production run
refs=(H2 H3)  # The references for RDF computation; length must equal rdfs
sels=(H2 H3)  # The other group in the RDF computation
cut_rdf=.2  # Cutoff for interactions calculated by RDF

#### NEMD INFORMATION #######
if [ "$NEMD" = "YES" ]
then
NEMD_pts=10  # Number of different cos-accelerations to use
cos_acc=(.01 .02 .03 .04 .05 .06 .07 .08 .09 .1)
NREPS=$NEMD_pts
fi

#Specify the path location for files
scripts_path=~/Scripts
conditions_path=~/"$Conditions_type"_Conditions  
exp_data_path=~/TDE_REFPROP_values
input_path=~/"$Compound"/Gromacs/Gromacs_input
if [ "$NEMD" = "YES" ]
then
output_path=~/"$Compound"/Gromacs/"$Conditions_type"_Viscosity/"$Model"_N"$Nmol"_NEMD #Code assumes that a folder already exists with this directory and the eps_sig_lam_MCMC file in it
else
output_path=~/"$Compound"/Gromacs/"$Conditions_type"_Viscosity/"$Model"_N"$Nmol"
fi

if [ "$MCMC_tors" = "YES" ]
then
output_path="$output_path"_MCMC_tors
echo "Using MCMC derived torsional parameters"

else

echo "Using fixed literature values for torsional parameters"

fi

jobfile="$output_path"/"$Compound"_job_"$job_date" 
cp "$scripts_path"/ArgonIanViscosity_practice.sh "$jobfile" #Keep track of what jobs have been submitted
#cat "$scripts_path"/McycloC6NPTsteps >> "$jobfile"  # Inellegant append
cat "$scripts_path"/run_single.sh >> "$jobfile"  # Another inellegant append
touch "$output_path"/warnings_job_"$job_date"

cd "$output_path" || error_report "Error switching to $output_path" "0" "0" "preprocessing"

touch press_all_log
touch Lbox_all

### Read the box size, that depends on number of molecules
if [ -f "$conditions_path"/"$Compound"_liquid_box_N"$Nmol" ]
then

while read line
do 
liquid_box+=("$line")
done < "$conditions_path"/"$Compound"_liquid_box_N"$Nmol"

else
echo "Unable to read box from $conditions_path"/"$Compound"_liquid_box_N"$Nmol"
exit 1
fi

# If pressure data is needed for an NPT run,
# Determine whether or not the pressure data is available.
if [ "$NPT" = "YES" ]
then
if [ -f "$conditions_path"/"$Compound"_press ]
then
echo Pressures ${press[@]} read from "$conditions_path"/"$Compound"_press
else
echo Pressures could not be read from "$conditions_path"/"$Compound"_press
exit 1
fi

### Read the pressure file into the array 'press'
while read line
do
press+=("$line")
done < "$conditions_path"/"$Compound"_press
fi

### Determine Temperature. In some cases temperature should be read from a file
# IF a temperature file exists, it will use that 
temp_search_path="$conditions_path"/"$Compound"_Temp
if [ "$Conditions_type" = "Saturation" ] || [ "$Conditions_type" = "$Model"_"Saturation" ]
then
temp_search_path="$conditions_path"/"$Compound"_Tsat
fi
echo Looking for temperatures at "$temp_search_path"
if [ -e "$temp_search_path" ]
then
while read line
do 
temps+=("$line")
done < "$temp_search_path"

# Otherwise, fill the array with copies of the given temperature
# Make the array the same length as the pressure
echo Temperatures ${temps[@]} read from "$temp_search_path"
else
for ((x=0; x < ${#liquid_box[@]}; x++))  # C style loop 
do
temps+=("$Temp")
done
echo Temperatures ${temps[@]} from default temperature used
fi

###Equilibration time 
# 0.002 ps time step

nsteps_eq=500000 # 1 ns total

# We're going to ignore normal step sizes
if [ "$OVERRIDE_STEPS" = "YES" ]
then
echo Overriding step numbers using equil=${equil_steps[*]}, prod=${prod_steps[*]}
# Use predefined step sizes
else
for ((x=0; x < jlim; x++))
do
equil_steps[$x]=$nsteps_eq
prod_steps[$x]=500000
done
fi
echo Step numbers : equil=${equil_steps[*]}, prod=${prod_steps[*]}


###Cut-off distance is approximately 3 sigma

rvdw=1.0 # [nm]

echo 'Cutoff of 1 nm'

### Assign force field parameters
### Inserted directly in top file


if [ "$lam_sim" = 12.0 ]
then

echo "Using native Lennard-Jones potential"
mdp_path="$lj_mdp_path"
#Originally I tried to have a tab_flag variable, but it was not working for tabulated because
#using "$tab_flag" in mdrun was different than echo. Fortunately, I discovered that Gromacs
#will just ignore the provided table if the vdwtype is cut-off instead of user.
#tab_flag=""

else

echo "Using tabulated potential"
mdp_path="$t_mdp_path"
#This also required copying tab_it into the output_path whereas it is typically output_path/MCMC_iMCMC
#tab_flag="-table $output_path/tab_it.xvg "

fi

### Copy experimental data files to output directory

# Copy in appropriate data for later post processing
if [ "$Conditions_type" = "Saturation" ]
then
cp "$exp_data_path"/"$Compound"_TDE_eta_sat.txt "$output_path"/TDE_eta_sat.txt
cp "$exp_data_path"/"$Compound"_REFPROP_eta_sat.txt "$output_path"/REFPROP_eta_sat.txt
else
cp "$exp_data_path"/"$Compound"_REFPROP_eta_"$Conditions_type".txt "$output_path"/REFPROP_eta_"$Conditions_type".txt
fi


### Create file and header for state point conditions if not already created
if [ ! -e "$output_path"/"$Conditions_type"Settings.txt ]
then
echo "NMol" "Length (nm)" "Temp (K)" > "$output_path"/"$Conditions_type"Settings.txt	
fi

### Loop through temperatures and densities		
jlim=$((jlim - 1))
batches=$((batches - 1))  # Limits for 0 indexed loops later

for j in $(seq $jlow $jlim) # Number of conditions to run

do

### Record state points
echo "$Nmol" "${liquid_box[j]}" "${temps[j]}" >> "$output_path"/"$Conditions_type"Settings.txt

nRep=0

#NREP_low=0
NREP_high=$((NREPS+NREP_low-1))

#NREP_low=$((NREP_low+35))
#NREP_high=$((NREP_high+35))

####

for iRep in $(seq 0 $batches) # Number of batches to run (0 9), 10 batches with 20 replicates is 200 parameter sets

do

for iMCMC in $(seq $NREP_low $NREP_high)
do

cd "$output_path" || error_report "Unable to change to $output_path" "$j" "$iMCMC" "start up" 

### Read in eps, sig, and lam from a file that contains the MCMC samples

echo iMCMC = "$iMCMC"

echo Run "$Conditions_type" Viscosity for Argon

####

mkdir -p MCMC_"$iMCMC"
cd MCMC_"$iMCMC" || error_report "Unable to change to MCMC_$iMCMC" "$j" "$iMCMC" "start up"

###Copy force field files
if [ "$Model" = 'Ian_UD' ]
then

cp "$input_path"/"$Compound".gro "$Compound".gro 
cp "$input_path"/"$Compound"_UD.top "$Compound".top
cp "$input_path"/tab_UD.xvg tab_it.xvg

sed -i -e s/some_Nmol/"$Nmol"/ "$Compound".top

fi

### Record state points, include header if creating file
### Moved this outside of loop
#if [ -e "$output_path"/MCMC_"$iMCMC"/"$Conditions_type"Settings.txt ]
#then
#echo "NMol" "Length (nm)" "Temp (K)" > "$output_path"/MCMC_"$iMCMC"/"$Conditions_type"Settings.txt
#fi

# Initialize the folders, copy files, and insert variables

cd "$output_path"/MCMC_"$iMCMC" || error_report "Unable to change to directory MCMC_$iMCMC" "$j" "$iMCMC" "start up"  #presumes this dir was made previously

mkdir -p Saturated
cd Saturated || error_report "Unable to change to directory Saturated" "$j" "$iMCMC" "start up" 

mkdir -p rho"$j"
cd    rho"$j" || error_report "Unable to change to directory rho$j" "$j" "$iMCMC" "start up"

#echo "$Nmol" "${liquid_box[j]}" "${Temp}" >> "$output_path"/MCMC_"$iMCMC"/"$Conditions_type"Settings.txt

mkdir -p Rep"$nRep"  
cd    Rep"$nRep" || error_report "Unable to change to directory Rep$nRep" "$j" "$iMCMC" "start up"

gmx insert-molecules -ci ../../../"$Compound".gro -nmol "$Nmol" -try 2000 -box "${liquid_box[j]}" "${liquid_box[j]}" "${liquid_box[j]}" -o "$Compound"_box.gro > insertout 2>> insertout

if [ "$RDF" = "YES" ]  # Do RDF setup
then
rdf_lim=$((rdfs - 1))  # Will be needed later for RDF computational loop
# Create the index file for later- pipes the necessary quit command to the interactive tool
echo q | gmx make_ndx -f "$Compound"_box.gro -o index.ndx > make_ndx.out 2>> make_ndx.out  
fi

#Copy the minimization files
echo mdp_path "$mdp_path"
cp "$mdp_path"/em_steep.mdp em_steep.mdp
cp "$mdp_path"/em_l-bfgs.mdp em_l-bfgs.mdp

sed -i -e s/some_rvdw/"$rvdw"/ em_steep.mdp
sed -i -e s/some_rvdw/"$rvdw"/ em_l-bfgs.mdp

mkdir -p NVT_eq
cd NVT_eq || error_report "Unable to change to directory NVT_eq" "$j" "$iMCMC" "start up"

# Copy the equilibration files and edit the temperature

cp "$mdp_path"/nvt_eq_no_output_"$BondType".mdp nvt_eq.mdp
sed -i -e s/some_temperature/"${temps[j]}"/ nvt_eq.mdp
sed -i -e s/some_nsteps/"${equil_steps[j]}"/ nvt_eq.mdp
sed -i -e s/some_rvdw/"$rvdw"/ nvt_eq.mdp
cur_ind=$((iMCMC - NREP_low))  # Find the proper cos_acceleration and subsitute
sed -i -e s/some_cos_acceleration/"${cos_acc[cur_ind]}"/ nvt_eq.mdp

# Still creating NVT_prod directory so that our codes are backwards compatible with data analysis (i.e. same directory hierarchy)

mkdir -p NVT_prod
cd NVT_prod || error_report "Unable to change to directory NVT_prod" "$j" "$iMCMC" "start up"
# Create new directory for viscosity run

mkdir -p NVT_vis
cd NVT_vis || error_report "Unable to change to directory NVT_vis" "$j" "$iMCMC" "start up"

# Copy the viscosity files and edit the temperature

cp "$mdp_path"/nvt_vis_no_xv_"$BondType".mdp nvt_vis.mdp
sed -i -e s/some_temperature/"${temps[j]}"/ nvt_vis.mdp
sed -i -e s/some_nsteps/"${prod_steps[j]}"/ nvt_vis.mdp
sed -i -e s/some_nstenergy/"${output_freq[j]}"/ nvt_vis.mdp
sed -i -e s/some_rvdw/"$rvdw"/ nvt_vis.mdp
sed -i -e s/some_cos_acceleration/"${cos_acc[cur_ind]}"/ nvt_vis.mdp

done # for loop over iMCMC

### Run the NPT steps to determine the box sizes
# Skip this if NPT != YES
if [ "$NPT" = "YES" ]
then
bash "$scripts_path"/ArgonNPTsteps "$Compound" "$Nmol" "${liquid_box[j]}" "$mdp_path" "$BondType" "${temps[j]}" "${press[j]}" "${equil_steps[j]}" "$rvdw" "$NREP_low" "$NREP_high" "$output_path" "$j" "$nRep" "$scripts_path" "$pin0" "$nt_eq" "$nt_vis" "${prod_steps[j]}"
fi

###First energy minimization

pinoffset=$pin0

for iMCMC in $(seq $NREP_low $NREP_high)
do

echo pinoffset = "$pinoffset"

cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep" || exit  #start fresh for do cycle instead of multiple "cd .."'s

gmx grompp -f em_steep.mdp -c "$Compound"_box.gro -p ../../../"$Compound".top -o em_steep.tpr > gromppout 2>> gromppout
#We now use a different approach for assigning nodes
#gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -pin on -pinoffset "$pinoffset" -pinstride 1 -ntomp 1 -nt 1 -nb cpu -deffnm em_steep > runout 2>> runout &
gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -nt 1 -nb cpu -pme cpu -deffnm em_steep > runout 2>> runout &
#gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -nt 1 -nb cpu -deffnm em_steep > runout 2>> runout &
cur_pid=$!
taskset -cp "$pinoffset" $cur_pid > /dev/null 2>&1
min_3_pids[${iMCMC}]=$cur_pid  # This is the third such step (others are in the subscript) hence 3

pinoffset=$((pinoffset+1))

done #for iMCMC

echo "Waiting for em_steep.tpr: Energy Minimization Part1"

for pid in ${min_3_pids[*]}  # Loop over array
do 
wait $pid
done

###Second energy minimization

pinoffset=$pin0

for iMCMC in $(seq $NREP_low $NREP_high)
do

echo pinoffset = "$pinoffset"

cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep" || error_report "Unable to change to directory Rep$nRep" "$j" "$iMCMC" "second energy minimzation NVT"  #start fresh for do cycle instead of multiple "cd .."'s

gmx grompp -f em_l-bfgs.mdp -c em_steep.gro -p ../../../"$Compound".top -o em_l_bfgs.tpr -maxwarn 1 >> gromppout 2>> gromppout
#gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -pin on -pinoffset "$pinoffset" -pinstride 1 -ntomp 1 -nt 1 -nb cpu -deffnm em_l_bfgs >> runout2 2>> runout2 &
gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -nt 1 -nb cpu -pme cpu -deffnm em_l_bfgs > runout2 2>> runout2 &
#gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -nt 1 -nb cpu -deffnm em_l_bfgs > runout2 2>> runout2 &
cur_pid=$!
taskset -cp "$pinoffset" $cur_pid > /dev/null 2>&1
min_4_pids[${iMCMC}]=$cur_pid

pinoffset=$((pinoffset+1))

done #for iMCMC

echo "Waiting for second energy minimization"

for pid in ${min_4_pids[*]}  # Iterate over 4th minimization array
do
wait $pid
done

###Equilibration period

pinoffset=$pin0

for iMCMC in $(seq $NREP_low $NREP_high)
do

echo pinoffset = "$pinoffset"

cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep"/NVT_eq || error_report "Unable to change to NVT_eq directory" "$j" "$iMCMC" "NVT equilibrium"  #start fresh for do cycle instead of multiple "cd .."'s

if ls ../step*.pdb 1> /dev/null 2>&1 #Remove these warning files
then
echo some energy minimizations might have failed for "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep" >> "$output_path"/warnings_job_"$job_date"
rm ../step*.pdb
fi

gmx grompp -f nvt_eq.mdp -c ../em_l_bfgs.gro -p ../../../../"$Compound".top -o nvt_eq.tpr > gromppout 2>> gromppout
#gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -pin on -pinoffset "$pinoffset" -pinstride 1 -nt "$nt_eq" -nb cpu -deffnm nvt_eq > runout 2>> runout &
Tempbox=${liquid_box[j]}  # This is the default for no NPT
if [ $NPT = YES ]
then
Tempbox=$(<../NPT_eq/NPT_prod/Lbox_NPT_ave)  # This is the default for NPT
fi
# Pass the proper box size to the subscript in case it needs to restart calculations (it starts from insert molecules)
"$scripts_path"/run_single.sh "$output_path"/MCMC_"$iMCMC"/tab_it.xvg "$nt_eq" cpu cpu nvt_eq "$pinoffset" "$j" "$nRep" "$output_path" "$NREP_low" "$NREP_high" "$Compound" "$Nmol" "$Tempbox" nvt &

pinoffset=$((pinoffset+nt_eq))

done #for iMCMC

echo Waiting for "$Conditions_type" equilibration

nit=0
maxit=3000000
ndone=$(cat "$output_path"/MCMC_*/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/runout | grep -c "GROMACS reminds you")
while [ $ndone -lt $((NREP_high+1)) ] && [ $nit -lt $maxit ]
do
nit=$((nit+1))
sleep 100s 
echo Waiting for "$Conditions_type" equilibration
ndone=$(cat "$output_path"/MCMC_*/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/runout | grep -c "GROMACS reminds you")
done

###Removed production period

###Viscosity period

pinoffset=$pin0
for iMCMC in $(seq $NREP_low $NREP_high)
do

echo pinoffset = "$pinoffset"

cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis || error_report "Unable to change to directory NVT_vis" "$j" "$iMCMC" "NVT viscosity"  #start fresh for do cycle instead of multiple "cd .."'s

gmx grompp -f nvt_vis.mdp -c ../../nvt_eq.gro -p ../../../../../../"$Compound".top -o nvt_vis.tpr > gromppout 2>> gromppout
#gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -pin on -pinoffset "$pinoffset" -pinstride 1 -nt "$nt_vis" -nb cpu -deffnm nvt_vis > runout 2>> runout & #Can use more cores in liquid phase since vapor phase will have already finished
gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -nt "$nt_vis" -nb cpu -pme cpu -deffnm nvt_vis -o nvt_vis.trr > runout 2>> runout &
#gmx mdrun -table "$output_path"/MCMC_"$iMCMC"/tab_it.xvg -nt "$nt_vis" -nb cpu -deffnm nvt_vis > runout 2>> runout &
taskset -cp "$pinoffset"-"$((pinoffset+nt_vis-1))" $! > /dev/null 2>&1

pinoffset=$((pinoffset+nt_vis))

done #for iMCMC


echo Waiting for "$Conditions_type" viscosities

nit=0
maxit=3000000
ndone=$(cat "$output_path"/MCMC_*/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis/runout | grep -c "GROMACS reminds you")
while [ $ndone -lt $((NREP_high+1)) ] && [ $nit -lt $maxit ]
do
nit=$((nit+1))
sleep 100s #00s 
echo Waiting for "$Conditions_type" viscosities
ndone=$(cat "$output_path"/MCMC_*/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis/runout | grep -c "GROMACS reminds you")
done

###Data analysis

### Uncomment this to have jobs stop half way through. This allows the data analysis to use fewer cores if the output files are enormous. ###
#############################################################################################################################################
##if [ "$j" -gt 1 ] #"${prod_steps[j]}" -gt 2000000 ]
##then
## Tried using an if statement but the "dones" were not parsed properly
cd "$output_path"/MCMC_"$iMCMC"/Saturated || error_report "Unable to change to Saturated directory" "$j" "$iMCMC" "post processing" 
#
NREP_low=$((NREP_low+NREPS))
NREP_high=$((NREP_high+NREPS))
#
echo iRep = "$iRep"
echo NREP_low = "$NREP_low"
echo NREP_high = "$NREP_high"
#
done # for iRep
#
cd "$output_path" || error_report "Unable to change to $output_path directory" "$j" "$iMCMC" "post processing" 
echo "In $PWD"
#
done  # For each j
#
cd "$output_path" || error_report "Unable to change to $output_path directory" "$j" "$iMCMC" "post processing" 
#
#bash "$scripts_path"/batch_compile_output "$Compound" "$BondType" "$batches" "$NREPS" "$jlim" "$jlow" "$NPT" "$Nmol" "$input_path" "$scripts_path" "$conditions_path" "$output_path" # "${prod_steps[j]}"
exit 0
#
#else
##############################################################################################################################################

echo "Waiting for post processing viscosity data"

if [ "$NEMD" = "YES" ]
then
echo "Processing for NEMD"
for iMCMC in $(seq $NREP_low $NREP_high)
do
cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis || error_report "Unable to change to NVT_vis" "$j" "$iMCMC" "post processing"  #start fresh for do cycle instead of multiple "cd .."'s
echo 34 | gmx energy -f nvt_vis.edr -s nvt_vis.tpr -skip 100000 > vis_out 2 >> vis_out   # Get 1/NEMD_VISCOSITY
awk -f "$scripts_path"/vis_arrange.awk < energy.xvg > visco_temp.xvg  # Convert to NEMD_VISCOSITY
awk -f "$scripts_path"/runavg.awk < visco_temp.xvg > visco.xvg  # Perform running average
vis_avg=$(<visco_avg.txt)  # Read in average
echo "${cos_acc[iMCMC]}	$vis_avg" >> "$output_path"/cosacc_vs_vis.txt
rm visco_temp.xvg  # Remove bulky files
rm energy.xvg
done
exit 0
else

for iMCMC in $(seq $NREP_low $NREP_high)
do

cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis || error_report "Unable to change to NVT_vis" "$j" "$iMCMC" "post processing"  #start fresh for do cycle instead of multiple "cd .."'s

# Don't need trajectories of eq and prod with viscosity
# Modified .mdp so that trajectories are not produced, i.e. this is no longer needed
#rm ../nvt_prod.trr
#rm ../../nvt_eq.trr

### Analyze trajectories for TCAF method
# No longer using TCAF to obtain viscosities
#echo 0 | gmx tcaf -f nvt_vis.trr -s nvt_vis.tpr > tcaf_out 2>> tcaf_out &

Lbox="${liquid_box[j]}"
if [ "$NPT" = "YES" ]  # If necessary, fetch the box size used due to NPT equilibration
then
Lbox=$(<../../../NPT_eq/NPT_prod/Lbox_NPT_ave)
fi
Vbox=$(echo $Lbox|awk '{print $1*$1*$1}')
echo "Using Lbox $Lbox and Vbox $Vbox in post processing MCMC $iMCMC j $j Rep $nRep"

### Analyze Green-Kubo and Einstein

echo "$Vbox" | gmx energy -f nvt_vis.edr -s nvt_vis.tpr -vis -nice 0 -skip 100000 > vis_out 2>> vis_out &
ls -la >> size_records.txt

done #for iMCMC

nit=0
maxit=60000 #Don't want this too high, so it will finish eventually
ndone=$(cat "$output_path"/MCMC_*/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis/vis_out | grep -c "GROMACS reminds you")
while [ $ndone -lt $((NREP_high+1)) ] && [ $nit -lt $maxit ]
do
nit=$((nit+1))
sleep 10s
echo "Still post processing viscosity data"
ndone=$(cat "$output_path"/MCMC_*/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis/vis_out | grep -c "GROMACS reminds you")
done

fi  # If statement for what to do in case of NEMD vs EMD

sleep 10s  # Added in because large files take time to finalize/move/copy

if [ "$RDF" = "YES" ]  # An RDF calculation has been requested
then
echo "Working on RDF's"
# Switch into every directory and perform RDF
for iMCMC in $(seq $NREP_low $NREP_high)
do
# Should we actually operate on this iMCMC?
if [ "$RDF_single" != "YES" ] || [ "$iMCMC" -eq 0 ]
then
cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis || exit  #start fresh for do cycle instead of multiple "cd .."'s
for i in $(seq 0 $rdf_lim)
do
# Name a file and run the requested rdf; there may be several
filename=${refs[i]}_v_${sels[i]}_rdf 
gmx rdf -f nvt_vis.trr -s nvt_vis.tpr -n ../../../index.ndx -ref ${refs[i]} -sel ${sels[i]} -o "$filename" -cut "$cut_rdf" >rdfout 2>>rdfout
gracebat -hdevice PNG "$filename".xvg >/dev/null 2>/dev/null
done  # With all requested RDFs
fi    # With decision of whether to operate this round
done  # With all iMCMC rdf runs
fi # if RDF=YES

echo "Removing large viscosity output files"

for iMCMC in $(seq $NREP_low $NREP_high)
do

cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis || error_report "Unable to change to NVT_vis directory" "$j" "$iMCMC" "post processing"  #start fresh for do cycle instead of multiple "cd .."'s

if [ -e vis_out ]
then
echo "Second attempt at size info gathering" > size_records.txt
ls -la >> size_records.txt
rm nvt_vis.trr
rm energy.xvg
rm nvt_vis.edr
rm enecorr.xvg
rm -f \#*
else
echo WARNING: No vis_out file for "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep" >> "$output_path"/warnings_job_"$job_date"
fi


### Compile the pressure values; Due to different storage for the bond types, requires nested ifs
if [ "$BondType" = harmonic ]
then

if [ "$Compound" = Ethane ]
then
sed -e '1,/A V E R A G E S/d' nvt_vis.log | grep -m 1 -A1 'Pressure' | tail -n 1 | awk '{print $1}' > press_log
elif [ "$Compound" = C3H8 ] || [ "$Compound" = IC4H10 ] || [ "$Compound" = NEOC5H12 ]
then
sed -e '1,/A V E R A G E S/d' nvt_vis.log | grep -m 1 -A1 'Pressure' | tail -n 1 | awk '{print $2}' > press_log
else
sed -e '1,/A V E R A G E S/d' nvt_vis.log | grep -m 1 -A1 'Pressure' | tail -n 1 | awk '{print $3}' > press_log
fi

else

if [ "$Compound" = Ethane ]
then
sed -e '1,/A V E R A G E S/d' nvt_vis.log | grep -m 1 -A1 'Pressure' | tail -n 1 | awk '{print $5}' > press_log
elif [ "$Compound" = C3H8 ] || [ "$Compound" = IC4H10 ] || [ "$Compound" = NEOC5H12 ]
then
sed -e '1,/A V E R A G E S/d' nvt_vis.log | grep -m 1 -A1 'Pressure' | tail -n 1 | awk '{print $1}' > press_log
else
sed -e '1,/A V E R A G E S/d' nvt_vis.log | grep -m 1 -A1 'Pressure' | tail -n 1 | awk '{print $2}' > press_log
fi
fi

cat "$output_path"/press_all_log press_log > "$output_path"/press_all_temp
cp "$output_path"/press_all_temp "$output_path"/press_all_log
rm "$output_path"/press_all_temp
###

if [ "$NPT" = "YES" ]  # Then we should fetch the box sizes...
then
### Compile the box sizes
cd "$output_path"/MCMC_"$iMCMC"/Saturated/rho"$j"/Rep"$nRep"/NPT_eq/NPT_prod || error_report "Unable to change to NPT_prod directory" "$j" "$iMCMC" "post processing" 
cat "$output_path"/Lbox_all Lbox_NPT_ave > "$output_path"/Lbox_all_temp
cp "$output_path"/Lbox_all_temp "$output_path"/Lbox_all
rm "$output_path"/Lbox_all_temp
fi

done #for iMCMC


cd "$output_path"/MCMC_"$iMCMC"/Saturated || error_report "Unable to change to Saturated directory" "$j" "$iMCMC" "post processing" 

#rm -f rho"$j"/Rep"$nRep"/NVT_eq/NVT_prod/NVT_vis/tcaf_all.xvg

NREP_low=$((NREP_low+NREPS))
NREP_high=$((NREP_high+NREPS))

echo iRep = "$iRep"
echo NREP_low = "$NREP_low"
echo NREP_high = "$NREP_high"

done # for iRep

cd "$output_path" || error_report "Unable to change to $output_path directory" "$j" "$iMCMC" "post processing" 
echo "In $PWD"

###GreenKubo_analyze for all MCMC parameter sets
python "$scripts_path"/GreenKubo_analyze.py --ilow 0 --ihigh $((NREP_low-1)) --nReps 1 --irho "$j" --sat

done  # For each j

cd "$output_path" || error_report "Unable to change to $output_path directory" "$j" "$iMCMC" "post processing" 
###Create plots to compare with experimental data and correlations
if [ "$Conditions_type" = "Saturation" ]
then
python "$scripts_path"/compare_TDE_REFPROP.py --comp "$Compound" --nrhomax $((j+1)) --sat
else
python "$scripts_path"/compare_TDE_REFPROP.py --comp "$Compound" --nrhomax $((j+1)) --"$Conditions_type"
fi

##fi # for "${prod_steps[j]}" -gt 2000000 #This did not work

exit 0

#######


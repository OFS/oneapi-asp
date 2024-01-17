#this script should create a folder/tarball containing the minimum necessary files that you need on a system to run OneAPI designs.

#find the current folder (ex: fseries_dk)
THIS_PLATFORM=`basename "$PWD"`
THIS_VARIANT=${THIS_PLATFORM/-/_}
echo "Creating a minimal tarball for use on ${THIS_PLATFORM} hardware systems."
echo "The base variant will be ${THIS_VARIANT}"
NEW_ASP_PATH="oneapi-asp/${THIS_PLATFORM}"
mkdir -p "${NEW_ASP_PATH}"
cd ${NEW_ASP_PATH}
cp -prf ../../board_env.xml .
mkdir -p hardware/ofs_${THIS_VARIANT}
mkdir -p hardware/ofs_${THIS_VARIANT}_usm
mkdir -p hardware/ofs_${THIS_VARIANT}_usm_iopipes
mkdir -p hardware/ofs_${THIS_VARIANT}_iopipes
cp -prf ../../hardware/ofs_${THIS_VARIANT}/board_spec.xml hardware/ofs_${THIS_VARIANT}/
cp -prf ../../hardware/ofs_${THIS_VARIANT}_usm/board_spec.xml hardware/ofs_${THIS_VARIANT}_usm/
cp -prf ../../hardware/ofs_${THIS_VARIANT}_usm_iopipes/board_spec.xml hardware/ofs_${THIS_VARIANT}_usm_iopipes/
cp -prf ../../hardware/ofs_${THIS_VARIANT}_iopipes/board_spec.xml hardware/ofs_${THIS_VARIANT}_iopipes/

cp -prf ../../linux64 .

cp -prf ../../hardware/ofs_${THIS_VARIANT}/blue_bits hardware/ofs_${THIS_VARIANT}/
cp -prf ../../hardware/ofs_${THIS_VARIANT}_usm/blue_bits hardware/ofs_${THIS_VARIANT}_usm/
cp -prf ../../hardware/ofs_${THIS_VARIANT}_usm_iopipes/blue_bits hardware/ofs_${THIS_VARIANT}_usm_iopipes/
cp -prf ../../hardware/ofs_${THIS_VARIANT}_iopipes/blue_bits hardware/ofs_${THIS_VARIANT}_iopipes/

cd ../..

tar czfh oneapi-asp-${THIS_PLATFORM}.tar.gz oneapi-asp/


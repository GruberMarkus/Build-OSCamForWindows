Clear-Host
Write-Host "AUTOMATED OSCAM COMPILER FOR WINDOWS"
Write-Host
Write-Host "The whole process is fully automated. You only need this script, internet access"
Write-Host "and at least 1 GB free disk space in the temp directory."
Write-Host
Write-Host "OSCam is compiled with all options enabled, plus PCSC, LIBUSB and OSCam-Emu."
Write-Host
Write-Host "Some steps may take several minutes, please be patient."
Write-Host

$tempPath = (Join-Path -Path $env:TEMP -ChildPath Build-OSCamForWindows)
if (-not (Test-Path -Path $tempPath -PathType Container)) {
  New-Item -Path $tempPath -ItemType Directory | Out-Null
}
Set-Location -Path $tempPath

# create cygwin-portable-installer-config.cmd
# last update: 2021-01-02
@'
:: set proxy if required (unfortunately Cygwin setup.exe does not have commandline options to specify proxy user credentials)
set PROXY_HOST=
set PROXY_PORT=8080

:: change the URL to the closest mirror https://cygwin.com/mirrors.html
set CYGWIN_MIRROR=https://mirrors.kernel.org/sourceware/cygwin/

:: one of: auto,64,32 - specifies if 32 or 64 bit version should be installed or automatically detected based on current OS architecture
set CYGWIN_ARCH=auto

:: choose a user name under Cygwin
set CYGWIN_USERNAME=root

:: select the packages to be installed automatically via apt-cyg
set CYGWIN_PACKAGES=subversion,make,dialog,gcc-core,libssl-devel,libusb1.0-devel,zip,unzip,patch

:: if set to 'yes' the local package cache created by cygwin setup will be deleted after installation/update
set DELETE_CYGWIN_PACKAGE_CACHE=yes

:: if set to 'yes' the apt-cyg command line package manager (https://github.com/kou1okada/apt-cyg) will be installed automatically
set INSTALL_APT_CYG=yes

:: if set to 'yes' the bash-funk adaptive Bash prompt (https://github.com/vegardit/bash-funk) will be installed automatically
set INSTALL_BASH_FUNK=no

:: if set to 'yes' Node.js (https://nodejs.org/) will be installed automatically
set INSTALL_NODEJS=no

:: if set to 'yes' Ansible (https://github.com/ansible/ansible) will be installed automatically
set INSTALL_ANSIBLE=no

:: if set to 'yes' AWS CLI (https://github.com/aws/aws-cli) will be installed automatically
set INSTALL_AWS_CLI=no

:: if set to 'yes' testssl.sh (https://testssl.sh/) will be installed automatically
set INSTALL_TESTSSL_SH=no

:: use ConEmu based tabbed terminal instead of Mintty based single window terminal, see https://conemu.github.io/
set INSTALL_CONEMU=no

:: set Mintty options, see https://cdn.rawgit.com/mintty/mintty/master/docs/mintty.1.html#CONFIGURATION
set MINTTY_OPTIONS=
'@ | Out-File -FilePath '.\cygwin-portable-installer-config.cmd' -Force -Encoding ascii

Write-Host
Write-Host "Downloading latest Cygwin Portable Installer ... " -NoNewline
Remove-Item -Force "cygwin-portable-installer.cmd" -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/vegardit/cygwin-portable-installer/master/cygwin-portable-installer.cmd' -OutFile 'cygwin-portable-installer.cmd' -UseBasicParsing

Write-Host "done."

Write-Host
if ((-not (Test-Path -PathType container -Path ".\cygwin")) -or (-not (Test-Path -PathType leaf -Path ".\cygwin-portable.cmd")) -or (-not (Test-Path -PathType leaf -Path ".\cygwin-portable-updater.cmd"))) {
  Write-Host "Installing Cygwin Portable ... " -NoNewline
  $p = Start-Process -FilePath ".\cygwin-portable-installer.cmd" -Wait -PassThru 
  Write-Host "done. Exit code $($p.Exitcode)."
} else {
  Write-Host "Updating Cygwin Portable ... " -NoNewline
  $p = Start-Process -FilePath ".\cygwin-portable-updater.cmd" -Wait -PassThru
  Write-Host "done. Exit code $($p.exitcode)."
}

if ($p.ExitCode -ne 0) {
  Write-Host "Exit code not 0, exiting." -ForegroundColor red
  exit 1
}



Write-Host
Write-Host "Downloading latest oscam source code and compiling it ... " -NoNewline

# shell script to run in Cygwin
$x = @'
cd ~/

echo "START TIMESTAMP: $(date --rfc-3339='seconds')"
echo "======================================================================"

echo
echo "PREPARATIONS"
echo "======================================================================"

if [ -d "oscam-svn" ]; then
  rm -r -f oscam-svn
fi

if [ -d "oscam-exe" ]; then
  rm -r -f oscam-exe
fi

if [ -d "oscam-zip" ]; then
  rm -r -f oscam-zip
fi

if [ -f "oscam-emu.patch" ]; then
  rm -r -f oscam-emu.patch
fi

echo
echo "SVN CHECKOUT OSCAM TRUNK"
echo "======================================================================"

svn checkout https://svn.streamboard.tv/oscam/trunk oscam-svn

cd oscam-svn

echo
echo "DOWNLOAD AND APPLY OSCAM-EMU.PATCH"
echo "======================================================================"
wget https://raw.githubusercontent.com/oscam-emu/oscam-emu/master/oscam-emu.patch
patch -p0 < oscam-emu.patch

echo
echo "BUILD PATCHED OSCAM"
echo "======================================================================"
make distclean
make allyesconfig
make USE_LIBUSB=1 USE_PCSC=1 PCSC_LIB='-lwinscard'

echo
echo "COPY BUILT EXE FILES AND RENAME THEM"
echo "======================================================================"

mkdir ~/oscam-exe

cd ~/oscam-exe
cp ~/oscam-svn/Distribution/*cygwin.exe* -t .

for i in $(ls *cygwin.exe*)
do
  mv $i ${i//cygwin.exe/cygwin}.exe
done

for z in $(ls oscam*.exe)
do
  mv $z oscam.exe
done

for i in $(ls list_smargo*.exe)
do
  mv $i list_smargo.exe
done

echo
echo "COPY DEPENDENT CYGWIN DLL FILES"
echo "======================================================================"

for i in $(ls *.exe)
do
  for x in $(cygcheck.exe ./$i)
  do
    if [[ $x =~ \\bin\\cyg.*\.dll ]]
    then
      cp $(cygpath -u $x) -t .
    fi
  done
done

echo
echo "CREATE OSCAM-INFO.txt"
echo "======================================================================"

./oscam.exe --build-info > oscam-info.txt

echo
echo "CREATE ZIP FILE"
echo "======================================================================"

mkdir ~/oscam-zip
zip -9 ~/oscam-zip/${z//exe/zip} *

echo
echo "END TIMESTAMP: $(date --rfc-3339='seconds')"
echo "======================================================================"
'@

Set-Content -Value (New-Object System.Text.UTF8Encoding $false).GetBytes(($x -ireplace "`r`n", "`n") + "`n") -Encoding Byte -Path '.\cygwin\home\root\make.sh' -Force -NoNewline
$p = Start-Process -FilePath ".\cygwin-portable.cmd" -ArgumentList '-c "~/make.sh 2>&1 | tee /tmp/oscam-buildlog.txt"' -Wait -PassThru
Move-Item -Path ".\cygwin\tmp\oscam-buildlog.txt" -Destination ".\cygwin\home\root\oscam-exe\"
Compress-Archive -Path ".\cygwin\home\root\oscam-exe\*"  -Update -DestinationPath ((Get-ChildItem ".\cygwin\home\root\oscam-zip\*.zip" | Select-Object -First 1).fullname)
Write-Host "done. Exit code $($p.exitcode)."
if ($p.ExitCode -ne 0) {
  Write-Host "Exit code not 0, exiting." -ForegroundColor red
  exit 1
}


if ($PSScriptRoot) {
  Write-Host
  Write-Host "Copying compiled binaries and dependent Cygwin DLLs ... " -NoNewline

  Set-Location $PSScriptRoot
  if (Test-Path -PathType container -Path ".\oscam-exe") {
    Remove-Item -Path ".\oscam-exe" -Recurse -Force
    New-Item -Path "." -Name "oscam-exe" -ItemType "directory" | Out-Null
  } else {
    New-Item -Path "." -Name "oscam-exe" -ItemType "directory" | Out-Null
  }

  if (-not (Test-Path -PathType container -Path ".\oscam-zip")) {
    New-Item -Path "." -Name "oscam-zip" -ItemType "directory" | Out-Null
  }

  $x = (Get-ChildItem -Path (Join-Path -Path $tempPath -ChildPath "cygwin\home\root\oscam-zip\*.zip") | Where-Object { ! $_.PSIsContainer } | Select-Object -First 1).fullname
  $y = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "oscam-zip") -ChildPath (Split-Path $x -Leaf)

  Copy-Item -Path $x -Destination $y -Force
  Expand-Archive -Path $y -DestinationPath (Join-Path -Path $PSScriptRoot -ChildPath "oscam-exe") -Force

  Write-Host "done."
}

Write-Host
Write-Host
Write-Host "Find 'oscam.exe', required Cygwin DLLs, 'oscam-info.txt' (output of 'oscam.exe --build-info'),"
Write-Host "and 'oscam-buildlog.txt' here:" 
if ($PSScriptRoot) {
  Write-Host ("  '" + (Join-Path -Path $PSScriptRoot -ChildPath "oscam-exe") + "'") 
} else {
  Write-Host ("  '" + (Join-Path -Path $tempPath -ChildPath "oscam-exe") + "'") 
}
Write-Host
Write-Host "Find a ZIP file containing all files required for redistribution here:" 
if ($PSScriptRoot) {
  Write-Host ("  '" + (Join-Path -Path $PSScriptRoot -ChildPath "oscam-zip") + "'") 
} else {
  Write-Host ("  '" + (Join-Path -Path $tempPath -ChildPath "oscam-zip") + "'") 
}

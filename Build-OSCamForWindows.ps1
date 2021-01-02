Clear-Host
Write-Host "AUTOMATED OSCAM COMPILER FOR WINDOWS" -ForegroundColor green
Write-Host
Write-Host "The whole process is fully automated. You only need this script, internet access and at least 1 GB free disk space."
Write-Host "oscam is compiled with all options enabled, plus support for PCSC and LIBUSB."
Write-Host "Some steps may take several minutes, please be patient."
Write-Host "Only errors are shown in this window."
Write-Host


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
set CYGWIN_PACKAGES=subversion,make,dialog,gcc-core,libssl-devel,libusb1.0-devel,zip,unzip

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
Write-Host "Downloading latest Cygwin Portable Installer"
Remove-Item -Force "cygwin-portable-installer.cmd" -ErrorAction SilentlyContinue

Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/vegardit/cygwin-portable-installer/master/cygwin-portable-installer.cmd' -OutFile 'cygwin-portable-installer.cmd' -UseBasicParsing

if (Test-Path -PathType container -Path ".\oscam-exe") {
    Remove-Item -Path ".\oscam-exe" -Recurse -Force
}
if (Test-Path -PathType container -Path ".\oscam-zip") {
    Remove-Item -Path ".\oscam-zip" -Recurse -Force
}

Write-Host "Done."


Write-Host
if ((-not (Test-Path -PathType container -Path ".\cygwin")) -or (-not (Test-Path -PathType leaf -Path ".\cygwin-portable.cmd")) -or (-not (Test-Path -PathType leaf -Path ".\cygwin-portable-updater.cmd"))) {
    Write-Host "Installing Cygwin Portable"
    $p = Start-Process -FilePath ".\cygwin-portable-installer.cmd" -Wait -PassThru 
    Write-Host "Done. Exit code $($p.Exitcode)."
} else {
    Write-Host "Updating Cygwin Portable"
    $p = Start-Process -FilePath ".\cygwin-portable-updater.cmd" -Wait -PassThru
    Write-Host "Done. Exit code $($p.exitcode)."
}

if ($p.ExitCode -ne 0) {
    Write-Host "Exit code not 0, exiting." -ForegroundColor red
    exit 1
}



Write-Host
Write-Host "Downloading latest oscam source code and compiling it"

# shell script to run in Cygwin
$x = @'
cd ~/

if [ ! -d "oscam-exe" ]; then
  rm -r -f oscam-zip
fi

if [ ! -d "oscam-zip" ]; then
  rm -r -f oscam-zip
fi

if [ ! -d "oscam-svn" ]; then
  svn checkout https://svn.streamboard.tv/oscam/trunk oscam-svn
  cd oscam-svn
else
  cd oscam-svn
  svn update
fi

make distclean
make allyesconfig
make USE_LIBUSB=1 USE_PCSC=1 PCSC_LIB='-lwinscard'

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

./oscam.exe --build-info > oscam-info.txt

mkdir ~/oscam-zip
zip -9 ~/oscam-zip/${z//exe/zip} *
'@

Set-Content -Value (New-Object System.Text.UTF8Encoding $false).GetBytes(($x -ireplace "`r`n", "`n") + "`n") -Encoding Byte -Path '.\cygwin\home\root\make.sh' -Force -NoNewline
$p = Start-Process -FilePath ".\cygwin-portable.cmd" -ArgumentList "-c '~/make.sh'"-Wait -PassThru
Write-Host "Done. Exit code $($p.exitcode)."
if ($p.ExitCode -ne 0) {
    Write-Host "Exit code not 0, exiting." -ForegroundColor red
    exit 1
}


Write-Host
Write-Host "Copying compiled binaries and dependent Cygwin DLLs"
New-Item -Path "." -Name "oscam-exe" -ItemType "directory" | Out-Null
New-Item -Path "." -Name "oscam-zip" -ItemType "directory" | Out-Null
Copy-Item -Path ".\cygwin\home\root\oscam-exe\*" -Destination ".\oscam-exe\" -Force
Copy-Item -Path ".\cygwin\home\root\oscam-zip\*" -Destination ".\oscam-zip\" -Force

Write-Host "Done."


Write-Host
Write-Host "The 'oscam-exe' folder contains 'oscam.exe' and dependent Cygwin DLLs," -ForegroundColor green
Write-Host "as well as 'oscam-info.txt' with the output of 'oscam.exe --build-info'." -ForegroundColor green
Write-Host
Write-Host "You can find a zipped archive of all files for redistribution in 'oscam-zip'." -ForegroundColor Green

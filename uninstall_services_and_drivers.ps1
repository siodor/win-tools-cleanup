Write-Host @'
┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Please don't run this script when you're logged in remotely through RDP, you will be disconnected! │
│ Use a console session to run this script                                                           │
└────────────────────────────────────────────────────────────────────────────────────────────────────┘

'@ -ForegroundColor Red -BackgroundColor Green
Read-Host -Prompt "Press any key if not on RDP or Ctrl+C to quit" 
Write-Host @'

Overview of steps:
	- Run PowerShell script
	- Shutdown VM
	- Modify VM parameters
	- Boot VM
	- Install XCP-ng Client Tools
	- Shutdown VM
	- Revert VM parameters
	- Boot VM
	- Let VM Reboot because of 
	- Run XCP-ng Client Tools installer again because Management Agent fails to install at first run.

'@
Read-Host -Prompt "If you wish to continue press any key or Ctrl+C to quit" 
Write-Host @'

Please make sure that you have:
		- Run PowerShell with Administrator privileges
		- "devcon.exe" in the same folder like the "uninstall_services_and_drivers.ps1" script
		
		How to get devcon.exe:
			- https://social.technet.microsoft.com/wiki/contents/articles/182.how-to-obtain-the-current-version-of-device-console-utility-devcon-exe.aspx
			- https://docs.microsoft.com/en-us/windows-hardware/drivers/devtest/devcon

'@
Read-Host -Prompt "Are above dependencies ok? To continue press any key or Ctrl+C to quit" 
Write-Host @'

Modify VM parameters:
		Shutdown your target Windows VM and modify it:
			- In Xen Orchestra disable "Windows Update tools"
			or run on Dom0:
			- xe vm-param-set uuid=<VM-UUID> has-vendor-device=false
		You can check what the current state of the parameter is:
			-  xe vm-param-get uuid=<VM-UUID> param-name=has-vendor-device
		This will prevent the Citrix XenServer drivers from coming back after the script was run.
		Without this the XCP-ng drivers won't be able to install, or will partially install and
		result in a mix of Citrix XenServer and XCP-ng drivers which will end in BSOD on next boot.

		For more information please see:
			- https://xcp-ng.org/blog/2018/04/23/the-future-of-vm-tools/
			- https://support.citrix.com/article/CTX215964

'@
Read-Host -Prompt "Is the VM prepared? To continue press any key or Ctrl+C to quit" 
Write-Host @'

This script will remove:

	The following services:
		- Citrix XenServer Health Check Service (part of XenCenter)
		- Citrix XenServer Installation and Update Agent
		- Citrix XenServer Windows Management Agent
		- XenServer PV Driver Monitor
		- XenServer Interface Service
	Delete XenServer related files in the following folders:
		- C:\Windows\System32\
		- C:\Windows\system32\drivers\
		- C:\Windows\system32\DriverStore\FileRepository\
	Delete all files in:
		- C:\Windows\SoftwareDistribution\Download

FYI: Some error messages might appear, this just means that certain things don't exist and can't be uninstalled.

'@
Read-Host -Prompt "If the above was understood press any key to continue or Ctrl+C to quit" 

#Disable Driver Updates through Windows Update
## This should disallow driver installations through Windows Update on Windows 7
## Values from DeviceSetup.admx, DeviceSetup.adml and various online sources
Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching -Name SearchOrderConfig -Value 0
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching -Name SearchOrderConfig -Value 0
## This should disallow driver installations through Windows Update on Windows 10
## Values from WindowsUpdate.admx, WindowsUpdate.adml and various online sources
## This will create in Windows Update the message:
## *Some settings are managed by your organisation
## View configured update policies
#############################################################################################################
# These registry keys will stay after the upgrade to prevent Windows Update from pulling in Citrix drivers. #
#############################################################################################################
New-Item -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update -Name ExcludeWUDriversInQualityUpdate -Value 1
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Update -Name ExcludeWUDriversInQualityUpdate -Value 1
New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name ExcludeWUDriversInQualityUpdate -Value 1
Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name ExcludeWUDriversInQualityUpdate -Value 1


#Disable + Stop, Windows Update, Windows Modules Installer and BITS to prevent trouble during removal of stuff
Get-Service wuauserv | ForEach-Object {Set-Service $_.Name -StartupType Disabled; Stop-Service $_.Name -Force}
Get-Service TrustedInstaller | ForEach-Object {Set-Service $_.Name -StartupType Disabled; Stop-Service $_.Name -Force}
Get-Service BITS | ForEach-Object {Set-Service $_.Name -StartupType Disabled; Stop-Service $_.Name -Force}

#Uninstall Management Agent
(Get-WmiObject -Class Win32_Product ` -Filter "Name = 'Citrix XenServer Windows Management Agent'").Uninstall()
#(Get-WmiObject -Class Win32_Product ` -Filter "Name = 'XCP-ng Windows Management Agent'").Uninstall()

#Remove Services
Get-Service *xen* | ForEach-Object {Set-Service $_.Name -StartupType Disabled; Stop-Service $_.Name; sc.exe delete $_.Name} #>
Get-Service InstallAgent | ForEach-Object {Set-Service $_.Name -StartupType Disabled; Stop-Service $_.Name; sc.exe delete $_.Name} #>

#Remove Drivers
Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XenServer PV Network Device*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XenServer PV Storage Host Adapter*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XenServer PV Network Class*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XenServer Interface*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XenServer PV Bus*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
#Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XCP-ng PV Network Device*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
#Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XCP-ng PV Storage Host Adapter*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
#Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XCP-ng PV Network Class*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
#Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XCP-ng Interface*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}
#Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like '*XCP-ng PV Bus*'} | ForEach-Object {pnputil.exe -f -d $_.InfName; .\devcon.exe remove $_.CompatID}


#Delete Service Files
Remove-Item -Path C:\Windows\System32\* -Include xen*.*

#Delete Drivers
#Remove-Item -Path C:\Windows\System32\drivers\* -Include xen*.*

#Delete driver source packages. This folder should be empty since we removed the packages with devcon.exe
Remove-Item -Path C:\Windows\System32\DriverStore\FileRepository -Include *xen* -Recurse

#Delete packages pulled from Windows Update
#unfortunately there's no easy way to find out which exact package belongs to the Citrix drivers, hence we'll have to empty the whole Windows Update downloads folder
Remove-Item -Path C:\Windows\SoftwareDistribution\Download\* -Recurse

#Enable + Start, Windows Update, Windows Modules Installer and BITS
#Get-Service BITS | ForEach-Object {Set-Service $_.Name -StartupType Manual}
#Get-Service TrustedInstaller | ForEach-Object {Set-Service $_.Name -StartupType Manual}
#Get-Service wuauserv | ForEach-Object {Set-Service $_.Name -StartupType Manual; Start-Service $_.Name}

#Enable Driver Updates through Windows Update
#Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching -Name SearchOrderConfig -Value 1
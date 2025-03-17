# variables to fill
$BIOS_Warning_URL = "blog storage path/BIOS_Update_Warning.zip"

$Get_MTM = ((Get-CimInstance Win32_ComputerSystem).Model.SubString(0, 4)).Trim()
$Log_File = "$env:SystemDrive\Windows\Debug\Remediation_BIOS_Update_$Get_MTM.log"
If(!(test-path $Log_File)){new-item $Log_File -type file -force | out-null}

$BIOS_Update_Success_File = "C:\Windows\Debug\BIOS_Update_Success_File.txt"
If(test-path $BIOS_Update_Success_File){remove-item $BIOS_Update_Success_File -Force}

Function Write_Log
	{
		param(
		$Message_Type,	
		$Message
		)
		
		$MyDate = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)		
		Add-Content $Log_File  "$MyDate - $Message_Type : $Message"		
		write-host  "$MyDate - $Message_Type : $Message"		
	}

Write_Log -Message_Type "INFO" -Message "Remediation script is running"

# Check if the warning is alrady opened
$BIOS_Warning_Status = (gwmi win32_process | Where {$_.commandline -like "*Warning_BIOS*"})				
$BIOS_Warning_Status2 = get-process | where {$_.MainWindowTitle -like "*Important update for your computer*"}				
If($BIOS_Warning_Status -ne $null)
	{
		$BIOS_Warning_Status.Terminate()
		Write_Log -Message_Type "INFO" -Message "The warning is already opened"		
		Write_Log -Message_Type "INFO" -Message "The warning has been closed"				
	}

If($BIOS_Warning_Status2 -ne $null)
	{
		$BIOS_Warning_Status2 | kill	
		Write_Log -Message_Type "INFO" -Message "The warning is already opened"		
		Write_Log -Message_Type "INFO" -Message "The warning has been closed"	
	}	


$WPF_Warning_ZIP_File = "C:\Windows\Temp\BIOS_Update_Warning.zip"
If(test-path $WPF_Warning_ZIP_File){remove-item $WPF_Warning_ZIP_File -force}
Write_Log -Message_Type "INFO" -Message "Downloading the last user warning"	
Try
	{
		Invoke-WebRequest -Uri $BIOS_Warning_URL -OutFile $WPF_Warning_ZIP_File | out-null
		Write_Log -Message_Type "INFO" -Message "Downloading the last user warning"	
	}
Catch
	{
		Write_Log -Message_Type "ERROR" -Message "Downloading the last user warning"	
		EXIT 1
	}	
	
$WPF_Warning_Export_Folder = "C:\Windows\Temp\WPF_Warning"
If(test-path $WPF_Warning_Export_Folder){remove-item $WPF_Warning_Export_Folder -recurse -force}
new-item $WPF_Warning_Export_Folder -type directory -force
Write_Log -Message_Type "INFO" -Message "Extracting user warning content"	
Try
	{
		Expand-Archive -Path $WPF_Warning_ZIP_File -DestinationPath $WPF_Warning_Export_Folder -Force
		Write_Log -Message_Type "SUCCESS" -Message "Extracting user warning content"		
	}
Catch
	{
		Write_Log -Message_Type "ERROR" -Message "Extracting user warning content"
		EXIT 1
	}


$BIOS_Export_Folder = "C:\Windows\Temp"
$BIOS_Update_EXE = "$BIOS_Export_Folder\BIOS_Update.exe"	
If(!(test-path $BIOS_Update_EXE))
	{
		Write_Log -Message_Type "INFO" -Message "Exporting last BIOS"	
		$Get_MTM = ((Get-CimInstance Win32_ComputerSystem).Model.SubString(0, 4)).Trim()	
		$WindowsVersion2 = "win10"
		$CatalogUrl = "https://download.lenovo.com/catalog/$Get_MTM`_$WindowsVersion2.xml"
		[System.Xml.XmlDocument]$CatalogXml = (New-Object -TypeName System.Net.WebClient).DownloadString($CatalogUrl)
		$PackageUrls = ($CatalogXml.packages.ChildNodes | Where-Object { $_.category -match "BIOS UEFI" }).location
		[System.Xml.XmlDocument]$PackageXml = (New-Object -TypeName System.Net.WebClient).DownloadString($PackageUrls)
		$baseUrl = $PackageUrls.Substring(0,$PackageUrls.LastIndexOf('/')+1)
		$Last_BIOS_Version = $PackageXml.Package.version	
		$BIOS_EXE_URL = $baseUrl + $PackageXml.Package.Files.Installer.File.Name
			
		try
			{
				Invoke-WebRequest -Uri $BIOS_EXE_URL -OutFile $BIOS_Update_EXE	| out-null
				Write_Log -Message_Type "SUCCESS" -Message "Last BIOS has been exported in $BIOS_Export_Folder"	
			}
		catch
			{
				Write_Log -Message_Type "ERROR" -Message "Can not export last BIOS"	
				EXIT 1
			}	
	}

Write_Log -Message_Type "INFO" -Message "Extracting last BIOS content"
$Extract_Folder_Path = "C:\Windows\Temp\BIOS_Extract"
If(test-path $Extract_Folder_Path){remove-item $Extract_Folder_Path -force -recurse}
new-item $Extract_Folder_Path -type directory -force | out-null
Try
	{
		Start-Process -FilePath ("$BIOS_Update_EXE") -ArgumentList "/VERYSILENT /DIR=$Extract_Folder_Path /EXTRACT=YES" -PassThru -Wait
		Write_Log -Message_Type "SUCCESS" -Message "Last BIOS has been extracted"
	}
Catch
	{
		Write_Log -Message_Type "ERROR" -Message "Error during last BIOS extraction"
		EXIT 1
	}
	
# Displaying the WPF warning 
Write_Log -Message_Type "INFO" -Message "Displaying user warning"
& "$WPF_Warning_Export_Folder\ServiceUI.exe" -process:explorer.exe C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe " -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $WPF_Warning_Export_Folder\Warning_BIOS.ps1"

# Fill the below variables
$BIOS_Delay_Days = 60

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

$Get_MTM = ((Get-CimInstance Win32_ComputerSystem).Model.SubString(0, 4)).Trim()
$Log_File = "$env:SystemDrive\Windows\Debug\Remediation_BIOS_Update_$Get_MTM.log"
If(!(test-path $Log_File)){new-item $Log_File -type file -force}

$WMI_computersystem = gwmi win32_computersystem
$Manufacturer = $WMI_computersystem.manufacturer
If($Manufacturer -eq "lenovo")
	{
		$Get_Current_Model = $WMI_computersystem.SystemFamily.split(" ")[1]
	}Else{
		$Get_Current_Model = $WMI_computersystem.Model		
	}

$OS_Ver = (Get-ciminstance Win32_OperatingSystem).Caption
If($OS_Ver -like "*10*"){$WindowsVersion = "win10"}ElseIf($OS_Ver -like "*11*"){$WindowsVersion = "win11"}
$CatalogUrl = "https://download.lenovo.com/catalog/$Get_MTM`_$WindowsVersion.xml"
try
	{
		[System.Xml.XmlDocument]$CatalogXml = (New-Object -TypeName System.Net.WebClient).DownloadString($CatalogUrl)

	}
catch
	{
		Write_Log -Message_Type "ERROR" -Message "Can not get BIOS info from Lenovo"		
		
		$Script:Output = "Can not get BIOS info from Lenovo"	
		# $Script:Exit_Code = 0	
		write-output $Output
		EXIT 0 		
	}

$PackageUrls = ($CatalogXml.packages.ChildNodes | Where-Object { $_.category -match "BIOS UEFI" }).location
If(($PackageUrls -ne $null) -and ($PackageUrls.Count -eq 1))
	{
		[System.Xml.XmlDocument]$PackageXml = (New-Object -TypeName System.Net.WebClient).DownloadString($PackageUrls)		
	}
Else
	{
		Write_Log -Message_Type "ERROR" -Message "Can not get BIOS info from Lenovo"		
		$Script:Output = "Can not get BIOS info from Lenovo"	
		write-output $Output
		EXIT 0 		
	}

$baseUrl = $PackageUrls.Substring(0,$PackageUrls.LastIndexOf('/')+1)
$Last_BIOS_Version = $PackageXml.Package.version	
If($Last_BIOS_Version -eq $null)
	{
		Write_Log -Message_Type "ERROR" -Message "Can not get BIOS info from Lenovo"	
		
		$Script:Output = "Can not get BIOS info from Lenovo"	
		write-output $Output
		EXIT 0 
	}
	
$BIOS_info = get-ciminstance win32_bios | select *
$BIOS_Maj_Version = $BIOS_info.SystemBiosMajorVersion 
$BIOS_Min_Version = $BIOS_info.SystemBiosMinorVersion 
$Get_Current_BIOS_Version = "$BIOS_Maj_Version.$BIOS_Min_Version"
Write_Log -Message_Type "INFO" -Message "Starting the detection script"

If($Get_Current_BIOS_Version -lt $Last_BIOS_Version)
	{
		$Last_BIOS_Severity = $PackageXml.Package.severity.type
		If($Last_BIOS_Severity -ne $null)
			{
				Write_Log -Message_Type "INFO" -Message "Last BIOS severity: $Last_BIOS_Severity"									
				If($Last_BIOS_Severity -eq "1")
					{
						Write_Log -Message_Type "INFO" -Message "New critical update"					
					}
				Else
					{
						Write_Log -Message_Type "INFO" -Message "New update not critical, no need to update"	
						EXIT 0						
					}					
			}
				
		$BIOS_Update_Success_File = "C:\Windows\Debug\BIOS_Update_Success_File.txt"
		If(test-path $BIOS_Update_Success_File){remove-item $BIOS_Update_Success_File -force}
					
		Write_Log -Message_Type "INFO" -Message "Model: $Get_MTM"
		Write_Log -Message_Type "INFO" -Message "Current BIOS version: $Get_Current_BIOS_Version"
		Write_Log -Message_Type "INFO" -Message "Last BIOS version: $Last_BIOS_Version"
		
		$New_BIOS_ReleaseDate = $PackageXml.Package.ReleaseDate 
		$Get_Current_Date = get-date
		
		Write_Log -Message_Type "INFO" -Message "Last BIOS date: $New_BIOS_ReleaseDate"
		Write_Log -Message_Type "INFO" -Message "Current date: $Get_Current_Date"
		Write_Log -Message_Type "INFO" -Message "Delay to accept the BIOS: $BIOS_Delay_Days"
		
		$Get_Converted_BIOS_Date = [datetime]::parseexact($New_BIOS_ReleaseDate, 'yyyy-MM-dd', $null)
		$Diff_LastBIOS_and_Today = $Get_Current_Date - $Get_Converted_BIOS_Date

		$Diff_in_days = $Diff_LastBIOS_and_Today.Days
		If(($Diff_in_days) -gt $BIOS_Delay_Days)
			{		
				Write_Log -Message_Type "INFO" -Message "Last BIOS version is greater than the delay"
				Write_Log -Message_Type "INFO" -Message "BIOS will be updated"
				
				$BIOS_EXE_URL = $baseUrl + $PackageXml.Package.Files.Installer.File.Name
				$BIOS_Name = $PackageXml.Package.Files.Installer.File.Name
				$BIOS_Export_Folder = "C:\Windows\Temp"
				$BIOS_EXE = "$BIOS_Export_Folder\BIOS_Update.exe"
				If(test-path $BIOS_EXE){remove-item $BIOS_EXE -force}
				
				Write_Log -Message_Type "INFO" -Message "Last BIOS URL: $BIOS_EXE_URL"
				Write_Log -Message_Type "INFO" -Message "BIOS will be exported in $BIOS_Export_Folder"		
					
				try
					{
						Invoke-WebRequest -Uri $BIOS_EXE_URL -OutFile $BIOS_EXE	
						Write_Log -Message_Type "SUCCESS" -Message "BIOS has been exported in $BIOS_Export_Folder"	
					}
				catch
					{
						Write_Log -Message_Type "ERROR" -Message "BIOS has not been exported in $BIOS_Export_Folder"	
					}
				write-output "To update (Delay >: $Diff_in_days)"				
				$Script:Output = "To update (Delay >: $Diff_in_days)"	
				$Script:Exit_Code = 1				
			}
		Else
			{	
				Write_Log -Message_Type "INFO" -Message "Last BIOS is lesser than the delay"
				Write_Log -Message_Type "INFO" -Message "BIOS will ot be updated yet"			

				$Script:Output = "Notuptodate but wait (Delai <: $Diff_in_days)"	
				$Script:Exit_Code = 0				
			}			
    }
Else
	{
		Write_Log -Message_Type "INFO" -Message "BIOS is already uptodate"
		$Script:Output = "Uptodate"
		$Script:Exit_Code = 0
	} 

If($Exit_Code -eq 0)
	{
		write-output $Output
		EXIT 0 
	}	
Else
	{
		write-output $Output
		EXIT 1		
	}
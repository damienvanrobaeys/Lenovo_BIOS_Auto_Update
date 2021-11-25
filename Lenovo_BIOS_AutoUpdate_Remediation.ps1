##################################################################################################
# 									Variables to fill
##################################################################################################

# Blog storage path containing the WPF warning
$BIOS_Warning_URL = ""

##################################################################################################
# 									Variables to fill
##################################################################################################

$Get_Current_Model = ((gwmi win32_computersystem).Model).Substring(0,4)
$BIOS_Update_Folder = "$env:temp\BIOSUpdate_$Get_Current_Model"
$BIOS_Update_File_Name = "BIOSUpdate_$Get_Current_Model"
$BIOS_Update_EXE = "$BIOS_Update_Folder\$BIOS_Update_File_Name.exe" 
$Get_New_BIOS_URL = "$BIOS_Update_Folder\BIOS_URL_$Get_Current_Model.txt"
$User_Continue_Process_File = "$BIOS_Update_Folder\BIOS_Update_Continue.txt"
$WPF_Warning_Export_Folder = "$BIOS_Update_Folder\WPF_Warning"
$WPF_Warning_ZIP_File = "$BIOS_Update_Folder\BIOS_Update_Warning.zip"	
	
# Security variables
$BIOS_Update_Downloaded = $False
$BIOS_EXE_Extracted = $False
$Suspend_Bitlocker_Success = $False
$Warning_GUI_Downloaded = $False
$Warning_ZIP_Extracted = $False

$Log_File = "$env:SystemDrive\Windows\Debug\Remediate_Update_BIOS_$Get_Current_Model.log"
If(!(test-path $Log_File)){new-item $Log_File -type file -force}

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

# Check if BIOS uodte URL is available on the device (provided by the detection script)
If(!(test-path $Get_New_BIOS_URL))
	{
		Write_Log -Message_Type "ERROR" -Message "File not found: $Get_New_BIOS_URL"	
		Break
	}


# Download the WPF warning for the user from the blob storage
Try
	{
		Invoke-WebRequest -Uri $BIOS_Warning_URL -OutFile $WPF_Warning_ZIP_File 	
		$Warning_GUI_Downloaded = $True	
	}
Catch
	{
		write-output "Issue while downlading WPF warning"
		EXIT 1
	}	
	
# If the WPF warning has been successfully downloaded, we will extract it
If($Warning_GUI_Downloaded -eq $True)
	{
		If(!(test-path $WPF_Warning_Export_Folder)){new-item $WPF_Warning_Export_Folder -Force -Type Directory}	
		Try
			{
				Expand-Archive -Path $WPF_Warning_ZIP_File -DestinationPath $WPF_Warning_Export_Folder -Force	
				$Warning_ZIP_Extracted = $True
			}
		Catch
			{
				write-output "Issue while extracting warning"
				EXIT 1
			}
	}

# If warning has been successfully extracted, we download the new BIOS version as EXE
If($Warning_ZIP_Extracted -eq $True)
	{	
		Try
			{
				$Get_New_BIOS_URL = Get-Content "$BIOS_Update_Folder\BIOS_URL_$Get_Current_Model.txt"	
				Invoke-WebRequest -Uri $Get_New_BIOS_URL -OutFile $BIOS_Update_EXE
				$BIOS_Update_Downloaded = $True
				Write_Log -Message_Type "INFO" -Message "Downloading BIOS"	
				Write_Log -Message_Type "SUCCESS" -Message "Downloading BIOS"												
			}
		Catch
			{
				write-output "Can not download the BIOS update"
				Write_Log -Message_Type "ERROR" -Message "Downloading BIOS"																		
				EXIT 1
			}

		# If BIOS EXE has been downloaded successfully, we will extract content
		If($BIOS_Update_Downloaded -eq $True)
			{
				Write_Log -Message_Type "INFO" -Message "Extracting BIOS"			
				$BIOS_Update_FileName = (Get-item $BIOS_Update_EXE).BaseName
				$Extract_Folder_Name = "$BIOS_Update_FileName" + "_$Get_Current_Model"
				$Extract_Folder_Path = "$BIOS_Update_Folder\BIOS_Extract"
				Try
					{
						Start-Process -FilePath ("$BIOS_Update_EXE") -ArgumentList "/VERYSILENT /DIR=$Extract_Folder_Path /EXTRACT=YES" -PassThru -Wait					
						$BIOS_EXE_Extracted = $True
						Write_Log -Message_Type "SUCCESS" -Message "Extracting BIOS"																
					}
				Catch
					{
						write-output "Issue while extracting BIOS update"							
						Write_Log -Message_Type "ERROR" -Message "Extracting BIOS"
						EXIT 1
					}
			}	
	}


# Si tout avant a été validé	
If(($BIOS_EXE_Extracted -eq $True) -and ($Warning_GUI_Downloaded -eq $True) -and ($Warning_ZIP_Extracted -eq $True) -and ($BIOS_Update_Downloaded -eq $True))
	{				
		# On affiche le warning WPF 
		# Display warning to user
		Write_Log -Message_Type "ERROR" -Message "Affichage de l'interface utilisateur"
		& "$WPF_Warning_Export_Folder\ServiceUI.exe" -process:explorer.exe C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe " -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $WPF_Warning_Export_Folder\Warning_BIOS.ps1"								
	}
##################################################################################################
# 									Variables to fill
##################################################################################################

# Blog storage path of WPF warning
$Warning_URL = ""

##################################################################################################
# 									Variables to fill
##################################################################################################

$Get_Current_Model = ((gwmi win32_computersystem).Model).Substring(0,4)
$BIOS_Update_Folder = "$env:temp\BIOSUpdate_$Get_Current_Model"
$BIOS_Update_File_Name = "BIOSUpdate_$Get_Current_Model_$Get_New_BIOS_Version"
$BIOS_Update_EXE = "$BIOS_Update_Folder\$BIOS_Update_File_Name.exe" 
$Get_New_BIOS_URL = "$BIOS_Update_Folder\BIOS_URL_$Get_Current_Model.txt"
$User_Continue_Process_File = "$BIOS_Update_Folder\BIOS_Update_Continue.txt"
$WPF_Warning_Export_Folder = "$BIOS_Update_Folder\WPF_Warning"
$WPF_Warning_ZIP_File = "$BIOS_Update_Folder\BIOS_Update_Warning.zip"
# $BIOS_Warning_URL = "https://stagrtdwpprddevices.blob.core.windows.net/biosmgmt/BIOS_Update_Warning.zip"
	
# Variable de sécurité	
$DockGen2_Firmware_Update_Downloaded = $False
$DockGen2_Firmware_EXE_Extracted = $False
$Suspend_Bitlocker_Success = $False
$Warning_GUI_Downloaded = $False
$Warning_ZIP_Extracted = $False


$Log_File = "$env:SystemDrive\Windows\Debug\Update_BIOS_$Get_Current_Model.log"
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

# Test if BIOS Update URL is available
If(!(test-path $Get_New_BIOS_URL))
	{
		Write_Log -Message_Type "ERROR" -Message "File not found: $Get_New_BIOS_URL"	
		EXIT 1
	}

#Download user WPF warning from blob storage
Try
	{
		Invoke-WebRequest -Uri $BIOS_Warning_URL -OutFile $WPF_Warning_ZIP_File 	
		$Warning_GUI_Downloaded = $True	
	}
Catch
	{
		write-output "Error during warning download"
		EXIT 1
	}	
	
# If WPF warning is successufully downloaded, we will extract ZIP content	
If($Warning_GUI_Downloaded -eq $True)
	{
		If(!(test-path $WPF_Warning_Export_Folder)){new-item $WPF_Warning_Export_Folder -Force -Type Directory}	
		Try
			{
				Expand-Archive -Path $WPF_Warning_ZIP_File -DestinationPath $WPF_Warning_Export_Folder		
				$Warning_ZIP_Extracted = $True
			}
		Catch
			{
				write-output "Error while downloading warning"
				EXIT 1
			}
	}

# If WPF ZIP has been extracted, we will download new BIOS version to EXE format
If($Warning_ZIP_Extracted -eq $True)
	{	
		Try
			{
				$Get_New_BIOS_URL = Get-Content "$BIOS_Update_Folder\BIOS_URL_$Get_Current_Model.txt"	
				Invoke-WebRequest -Uri $Get_New_BIOS_URL -OutFile $BIOS_Update_EXE 	
				$BIOS_Update_Downloaded = $True
				Write_Log -Message_Type "INFO" -Message "Download new BIOS"	
				Write_Log -Message_Type "SUCCESS" -Message "Download new BIOS"													
			}
		Catch
			{
				write-output "New BIOS not downloaded"
				Write_Log -Message_Type "ERROR" -Message "Download new BIOS"																			
				EXIT 1
			}

		# If EXE has been downloaded, we will extract content
		If($BIOS_Update_Downloaded -eq $True)
			{
				Write_Log -Message_Type "INFO" -Message "Extraction du nouveau BIOS"			
				$BIOS_Update_FileName = (Get-item $BIOS_Update_EXE).BaseName
				$Extract_Folder_Name = "$BIOS_Update_FileName" + "_$Get_Current_Model"
				$Extract_Folder_Path = "$BIOS_Update_Folder\$BIOS_Extract_Folder_Name"
				Try
					{
						Start-Process -FilePath ("$BIOS_Update_EXE") -ArgumentList "/VERYSILENT /DIR=$Extract_Folder_Path /EXTRACT=YES" -PassThru -Wait					
						$BIOS_EXE_Extracted = $True
						Write_Log -Message_Type "SUCCESS" -Message "Extraction du nouveau BIOS"																
					}
				Catch
					{
						write-output "Can not extract BIOS update content"							
						Write_Log -Message_Type "ERROR" -Message "Extract BIOS"
						EXIT 1
					}
			}	
	}

# If everything is OK
If(($BIOS_EXE_Extracted -eq $True) -and ($Warning_GUI_Downloaded -eq $True) -and ($Warning_ZIP_Extracted -eq $True) -and ($BIOS_Update_Downloaded -eq $True))
	{
		# Displays WPF warning
		& "$WPF_Warning_Export_Folder\ServiceUI.exe" -process:explorer.exe C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe " -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $WPF_Warning_Export_Folder\Warning_BIOS.ps1"								

		# If user has clicked on final next
		If(test-path $User_Continue_Process_File)
			{			
				# Stop Bitlocker
				Write_Log -Message_Type "INFO" -Message "Arrêt de Bitlocker"																
				$Check_Bitlocker_Status = Get-BitLockerVolume -MountPoint $env:SystemDrive | Select-Object -Property ProtectionStatus
				If ($Check_Bitlocker_Status.ProtectionStatus -eq "On") 
					{
						Try
							{
								# Bitlocker will start at next reboot
								Suspend-BitLocker -MountPoint $env:SystemDrive  -RebootCount 1 | out-null
								$Suspend_Bitlocker_Success = $True			
								Write_Log -Message_Type "SUCCESS" -Message "Stop Bitlocker"	
								Write_Log -Message_Type "SUCCESS" -Message "Bitlocker will be enabled at next reboot"																														
							}
						Catch
							{
								Write_Log -Message_Type "ERROR" -Message "Stop Bitlocker"	
								write-output "Can not stop Bitlocker"																	
								EXIT 1
							}
					}	
				Else
					{
						$Suspend_Bitlocker_Success = $True			
						Write_Log -Message_Type "SUCCESS" -Message "Bitlocker not enable"						
					}
										
				# If Bitclocker has been stopped, we will update BIOS				
				If($Suspend_Bitlocker_Success -eq $True)
					{
						# BIOS Update installer
						$WINUTP_Installer = "WINUPTP64.exe"
						# BIOS Update installer silent switch
						$Silent_Switch = "-s"			
						# Path of the BIOS installer
						$WINUTP_Install_Path = "$Extract_Folder_Path\$WINUTP_Installer"	
						# BIOS Update log name
						$WINUTP_Log_File = "winuptp.log"	
						# BIOS Update log path
						$WINUTP_Log_Path = "$Extract_Folder_Path\$WINUTP_Log_File"	
								
						Write_Log -Message_Type "INFO" -Message "Update BIOS"	
						If(test-path $WINUTP_Install_Path)
							{
								Try
									{
										$Update_Process = Start-Process -FilePath $WINUTP_Installer -WorkingDirectory $Extract_Folder_Path -ArgumentList $Silent_Switch -PassThru -Wait
										If(($Update_Process.ExitCode) -eq 1) 
											{
												If(test-path $WINUTP_Log_Path)
													{
														$Check_BIOSUpdate_Status_FromLog = ((Get-content $WINUTP_Log_Path | where-object { $_ -like "*BIOS Flash completed*"}) -ne "")		
														If($Check_BIOSUpdate_Status_FromLog -ne $null)
															{
																Write_Log -Message_Type "SUCCESS" -Message "Update BIOS"	
																Write_Log -Message_Type "INFO" -Message "Waiting for restart"	
																write-output "Update BIOS OK - Waiting for restart"
																start-process -WindowStyle hidden powershell.exe "$WPF_Warning_Export_Folder\Restart_Computer.ps1" 			
																EXIT 0			
															}
														Else
															{									
																Write_Log -Message_Type "ERROR" -Message "Update BIOS"	
																write-output "BIOS has not been updated"
																EXIT 1
															}
													}
											}			
									}
								Catch
									{
										Write_Log -Message_Type "ERROR" -Message "Update BIOS"	
										write-output "BIOS has not been updated"
										EXIT 1							
									}			
							}
					}										
			}	
		Else
			{
				Write_Log -Message_Type "INFO" -Message "User canceled the update process"	
				EXIT 1
			}
	}
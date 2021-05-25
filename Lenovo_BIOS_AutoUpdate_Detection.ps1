##################################################################################################
# 									Variables to fill
##################################################################################################

# Blog storage path of LZ4 DLL
$LZ4_DLL = ""

# Delay for BIOS update - if BIOS release is older than the delay, it will continue the process
$BIOS_Delay_Days = 90

# Chemin du warning user sur le blog storage
$BIOS_Warning_URL = ""

##################################################################################################
# 									Variables to fill
##################################################################################################


$WMI_computersystem = gwmi win32_computersystem
$Manufacturer = $WMI_computersystem.manufacturer
If($Manufacturer -ne "LENOVO")
	{
		write-output "Manufacturer is not Lenovo"	
		EXIT 0	
	}
Else
	{	
		$Script:currentuser = $WMI_computersystem | select -ExpandProperty username
		$Script:process = get-process logonui -ea silentlycontinue
		If($currentuser -and $process)
			{							
				write-output "Computer is locked"	
				EXIT 0
			}
		Else
			{	
				$LZ4_DLL_Path = "$env:TEMP\LZ4.dll"
				$DLL_Download_Success = $False
				If(!(test-path $LZ4_DLL_Path))
					{
						# $LZ4_DLL = "https://stagrtdwpprddevices.blob.core.windows.net/biosmgmt/LZ4.dll"
						Try
							{
								Invoke-WebRequest -Uri $LZ4_DLL -OutFile "$LZ4_DLL_Path" 	
								$DLL_Download_Success = $True		
							}
						Catch
							{
								write-output "Ca not download DLL LZ4"
								EXIT 0
							}	
					}
				Else
					{
						$DLL_Download_Success = $True		
					}

					
				If($DLL_Download_Success -eq $True)
					{
						[System.Reflection.Assembly]::LoadFrom("$LZ4_DLL_Path") | Out-Null

						Function Decode-WithLZ4 ($Content,$originalLength)
						{
							$Bytes =[Convert]::FromBase64String($Content)
							$OutArray = [LZ4.LZ4Codec]::Decode($Bytes,0, $Bytes.Length,$originalLength)
							$rawString  = [System.Text.Encoding]::UTF8.GetString($OutArray)
							return $rawString
						}

						Class Lenovo{
							Static hidden [String]$_vendorName = "Lenovo"
							hidden [Object[]] $_deviceCatalog
							hidden [Object[]] $_deviceImgCatalog  
							
							Lenovo()
							{
								$this._deviceCatalog = [Lenovo]::GetDevicesCatalog()
								$this._deviceImgCatalog = $null
							}

							Static hidden [Object[]] GetDevicesCatalog()
							{
								$result = Invoke-WebRequest -Uri "https://pcsupport.lenovo.com/us/en/api/v4/mse/getAllProducts?productId=" -Headers @{
								"Accept"="application/json, text/javascript, */*; q=0.01"
								  "Referer"="https://pcsupport.lenovo.com/us/en/"
								  "X-CSRF-Token"="2yukcKMb1CvgPuIK9t04C6"
								  "User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.97 Safari/537.36"
								  "X-Requested-With"="XMLHttpRequest"
								}


								$JSON = ($result.Content | ConvertFrom-Json)
								$rawString = Decode-WithLZ4 -Content $JSON.content -originalLength $JSON.originLength 
								$jsonObject = ($rawString | ConvertFrom-Json)

								return $jsonObject
							}

							[Object[]]FindModel($userInputModel)
							{
								$SearchResultFormatted = @()
								$userSearchResult = $this._deviceCatalog.Where({($_.Name -match $userInputModel) -and ($_.Type -eq "Product.SubSeries")})	
								foreach($obj in $userSearchResult){
									$SearchResultFormatted += [PSCustomObject]@{
										Name=$obj.Name;
										Guid=$obj.ProductGuid;
										Path=$obj.Id;
										Image=$obj.Image
									} 
								}
								return $SearchResultFormatted
							}

							hidden [Object[]] GetModelWebResponse($modelGUID)
							{
								$DownloadURL = "https://pcsupport.lenovo.com/us/en/api/v4/downloads/drivers?productId=$($modelGUID)"						
								$SelectedModelwebReq = Invoke-WebRequest -Uri $DownloadURL -Headers @{
								}
								$SelectedModelWebResponse = ($SelectedModelwebReq.Content | ConvertFrom-Json)   
								return $SelectedModelWebResponse
							}

							hidden [Object[]]GetAllSupportedOS($webresponse)
							{
								
								$AllOSKeys = [Array]$webresponse.body.AllOperatingSystems
								$operatingSystemObj= $AllOSKeys | Foreach { [PSCustomObject]@{ Name = $_; Value = $_}}
								return $operatingSystemObj
							}
							
							hidden [Object[]]LoadDriversFromWebResponse($webresponse)
							{
								$DownloadItemsRaw = ($webresponse.body.DownloadItems | Select-Object -Property Title,Date,Category,Files,OperatingSystemKeys)
								$DownloadItemsObj = [Collections.ArrayList]@()

								ForEach ($item in $DownloadItemsRaw | Where{$_.Title -notmatch "SCCM Package"})
								{
									[Array]$ExeFiles = $item.Files | Where-Object {($_.TypeString -notmatch "TXT")} 
									$current = [PSCustomObject]@{
										Title=$item.Title;
										Category=$item.Category.Name;
										Class=$item.Category.Classify;
										OperatingSystemKeys=$item.OperatingSystemKeys;
										
										Files= [Array]($ExeFiles |  ForEach-Object {  
											if($_){
												[PSCustomObject]@{
													IsSelected=$false;
													ID=$_.Url.Split('/')[-1].ToUpper().Split('.')[0];
													Name=$_.Name;
													Size=$_.Size;
													Type=$_.TypeString;
													Version=$_.Version
													URL=$_.URL;
													Priority=$_.Priority;
													Date=[DateTimeOffset]::FromUnixTimeMilliseconds($_.Date.Unix).ToString("MM/dd/yyyy")
												}
											}
										})										
									}
									$DownloadItemsObj.Add($current) | Out-Null
								}
								return $DownloadItemsObj
							}
						}

						$Model_Found = $False
						$Get_Current_Model_MTM = ((gwmi win32_computersystem).Model).Substring(0,4)
						$Get_Current_Model_FamilyName = (gwmi win32_computersystem).SystemFamily.split(" ")[1]
						$BIOS_Version = gwmi win32_bios
						$BIOS_Maj_Version = $BIOS_Version.SystemBiosMajorVersion 
						$BIOS_Min_Version = $BIOS_Version.SystemBiosMinorVersion 
						$Get_Current_BIOS_Version = "$BIOS_Maj_Version.$BIOS_Min_Version"
						$RunspaceScopeVendor = [Lenovo]::new()
						
						$Search_Model = $RunspaceScopeVendor.FindModel("$Get_Current_Model_MTM")
						$Get_GUID = $Search_Model.Guid 
						If($Get_GUID -eq $null)
							{
								$Search_Model = $RunspaceScopeVendor.FindModel("$Get_Current_Model_FamilyName")	
								$Get_GUID = $Search_Model.Guid 				
								If($Get_GUID -eq $null)
									{
										write-output "Modèle introuvable ou problème de vérification"	
										EXIT 0
									}		
								Else
									{
										$Model_Found = $True
									}	
							}
						Else
							{
								$Model_Found = $True
							}
											
						If($Model_Found -eq $True)
							{
								$Get_GUID = $Search_Model.Guid 
								$wbrsp 	= $RunspaceScopeVendor.GetModelWebResponse("$Get_GUID")
								$OSCatalog = $RunspaceScopeVendor.GetAllSupportedOS($wbrsp) 
								$DriversModeldatas 	= $RunspaceScopeVendor.LoadDriversFromWebResponse($wbrsp) 
								$DriversModelDatasForOsType = [Array]($DriversModeldatas | Where-Object {($_.OperatingSystemKeys -contains 'Windows 10 (64-bit)' )} )

								$Get_BIOS_Update = $DriversModelDatasForOsType | Where {($_.Title -like "*BIOS Update*")}
								$Get_BIOS_Update = $Get_BIOS_Update.files  | Where {$_.Type -eq "EXE"}
								$Get_New_BIOS_Version = $Get_BIOS_Update.version
														
								$Get_New_BIOS_URL = $Get_BIOS_Update.URL
								$Get_New_BIOS_Date = $Get_BIOS_Update.Date
								$Get_Converted_BIOS_Date = [Datetime]::ParseExact($Get_New_BIOS_Date, 'MM/dd/yyyy', $null)							
								
								$BIOS_Update_File_Name = "BIOSUpdate_$Get_Current_Model_$Get_New_BIOS_Version"
								$BIOS_Update_Path = "$env:temp\$BIOS_Update_File_Name"
								$BIOS_Update_Folder = "$env:temp\BIOSUpdate_$Get_Current_Model_MTM"
								If(test-path $BIOS_Update_Folder){Remove-item $BIOS_Update_Folder -Force -Recurse}
								new-item $BIOS_Update_Folder -Force -Type Directory | out-null
								$Get_New_BIOS_URL | out-file "$BIOS_Update_Folder\BIOS_URL_$Get_Current_Model_MTM.txt"

								If($Get_Current_BIOS_Version -lt $Get_New_BIOS_Version)
									{
										$Get_Current_Date = get-date
										$Diff_LastBIOS_and_Today = $Get_Current_Date - $Get_Converted_BIOS_Date
										$Diff_in_days = $Diff_LastBIOS_and_Today.Days
										If($Diff_in_days -gt $BIOS_Delay_Days)
											{		
												write-output "($Get_Current_Model_FamilyName) Older than 180 jours ($Diff_in_days)"
												EXIT 1
											}
										Else
											{		
												write-output "($Get_Current_Model_FamilyName) BIOS date Less than 180 jours ($Diff_in_days)"
												EXIT 0
											}																					
									}
								Else
									{
										write-output "No new version -  Current version: $Get_Current_BIOS_Version ($Get_Current_Model_FamilyName)"
										EXIT 0
									}			
							}	
					}
			}	
	}

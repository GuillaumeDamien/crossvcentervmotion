####################################################################################
# Author: Romain Decker <romain@cloudmaniac.net>
# Evolution : Guillaume & Yassine
####################################################################################

# Load Check Chart fonction
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
cd $dir

$VMs = Import-Csv -Path "List_VM.csv" -Delimiter ";"

####################################################################################
# Variables
####################################################################################
# vCenter Source Details (SSO Domain A)
$SrcvCenter = 'vCenter.source'
$DstvCenter = 'vCenter.cible'
$vCenterUserName = 'compte_avec_droits_vcenter'
$CenterPassword = 'xxxxxx'

####################################################################################
# Function GetPortGroupObject
function GetPortGroupObject1 {
    Param(
        [Parameter(Mandatory=$True)]
        [string]$PortGroup
    )

    if (Get-VDPortGroup -Name $TMPVMs.DstPortGroup1 -ErrorAction SilentlyContinue) {
        return Get-VDPortGroup -Name $TMPVMs.DstPortGroup1
    }
    else {
        if (Get-VirtualPortGroup -Name $TMPVMs.DstPortGroup1 -ErrorAction SilentlyContinue) {
            return Get-VirtualPortGroup -Name $TMPVMs.DstPortGroup1
        }
        else {
            Write-Host "The PorGroup '$TMPVMs.DstPortGroup1' doesn't exist in the destination vCenter"
            exit
        }
    }
}
function GetPortGroupObject2 {
    Param(
        [Parameter(Mandatory=$True)]
        [string]$PortGroup
    )

    if (Get-VDPortGroup -Name $TMPVMs.DstPortGroup2 -ErrorAction SilentlyContinue) {
        return Get-VDPortGroup -Name $TMPVMs.DstPortGroup2
    }
    else {
        if (Get-VirtualPortGroup -Name $TMPVMs.DstPortGroup2 -ErrorAction SilentlyContinue) {
            return Get-VirtualPortGroup -Name $TMPVMs.DstPortGroup2
        }
        else {
            Write-Host "The PorGroup '$TMPVMs.DstPortGroup2' doesn't exist in the destination vCenter"
            exit
        }
    }
}

function Drawline {
    for($i=0; $i -lt (get-host).ui.rawui.buffersize.width; $i++) {write-host -nonewline -foregroundcolor cyan "-"}
}

####################################################################################
# Connect to vCenter Servers
Connect-ViServer -Server $SrcvCenter -User $vCenterUserName -Password $CenterPassword -WarningAction Ignore | out-null
write-Host -foregroundcolor Yellow "Connected to Source vCenter : $SrcvCenter..."
Connect-ViServer -Server $DstvCenter -User $vCenterUserName -Password $CenterPassword -WarningAction Ignore | out-null
write-Host -foregroundcolor Yellow "Connected to Destination vCenter : $DstvCenter..."
$ListVMMigree = @() 
####################################################################################
# vMotion :)
foreach ( $TMPVMs in $VMs)
{
	$vm = Get-VM $TMPVMs.name
	$CurrentvCenter = $vm.Uid.Split(":")[0].Split("@")[1]
	### Vérifier si la VM est toujours dans le vCenter sources
	if ($CurrentvCenter -match $SrcvCenter)
	{
		$destination = Get-VMHost -Location $TMPVMs.cluster | Select-Object -First 1
		$destinationDatastore = Get-Datastore $TMPVMs.Datastore  | ?{$_.datacenter -match "@nom_datacenter"}
		$networkAdapter = Get-NetworkAdapter -VM $TMPVMs.name
		
		## Vérifier les cartes actuelles et mettre la correspondance 
		$destinationPortGroup = @()
		foreach ($TMPnetworkAdapter in $networkAdapter) 
		{
			switch($TMPnetworkAdapter.NetworkName)
			{
				'vProduction' {$destinationPortGroup += GetPortGroupObject1 -PortGroup $TMPVMs.DstPortGroup1 | ?{$_.vdswitch.datacenter -match "@FR_PANTIN_PA4_DataCenter 1"}}
				'vBackup' {$destinationPortGroup += GetPortGroupObject2 -PortGroup $TMPVMs.DstPortGroup2 | ?{$_.vdswitch.datacenter -match "@FR_PANTIN_PA4_DataCenter 1"}}
				default {$destinationPortGroup += GetPortGroupObject1 -PortGroup $TMPVMs.DstPortGroup1 | ?{$_.vdswitch.datacenter -match "@FR_PANTIN_PA4_DataCenter 1"}}
			}

		}
		
		## Vérifier si la VM a bien les bons portgroup
		if ($destinationPortGroup -ne $null) 
		{
			$task = $vm | Move-VM -Destination $destination -NetworkAdapter $networkAdapter -PortGroup $destinationPortGroup -Datastore $destinationDatastore -ErrorAction Stop -RunAsync 
								
			while($task.state -eq "Running")
			 {
			   Start-Sleep 5
			   write-host -foregroundcolor yellow "$($TMPVMs.name) : Migration en cours"
			   $task = Get-Task -ID $task.id
			 }

			####################################################################################
			# Display VM information after vMotion
			write-host -foregroundcolor Cyan "La VM tourne sur:"
			Drawline
						
			$vm = Get-VM $TMPVMs.name
			$CurrentvCenter = $vm.Uid.Split(":")[0].Split("@")[1]
			$DC = (get-vm $VM | get-datacenter).name
			$networkAdapter = Get-NetworkAdapter -VM $TMPVMs.name
			$Cluster = (get-vm $vm | get-cluster).name
			$destinationDatastore = (Get-VM $TMPVMs.name | Get-Datastore).name
			$onlinetest = Test-Connection -computername $TMPVMs.name -Count 1 -quiet
			 switch ($onlinetest)
				{
				 $true {$PING="OK"}
				 $false {$PING="NOK"} 
				 Default {"N/A"}
				}
				
			$NodeOutput  = New-Object -Type PSObject            
			$NodeOutput | Add-Member -MemberType NoteProperty -Name "Name" -value $TMPVMs.name
			$NodeOutput | Add-Member -MemberType NoteProperty -Name "Cluster" -value $Cluster
			$NodeOutput | Add-Member -MemberType NoteProperty -Name "DS" -value $destinationDatastore
			$NodeOutput | Add-Member -MemberType NoteProperty -Name "Ping" -value $Ping
			$NodeOutput | Add-Member -MemberType NoteProperty -Name "DC" -value $DC
			$NodeOutput | Add-Member -MemberType NoteProperty -Name "vCenter" -value $CurrentvCenter
			$ListVMMigree += $NodeOutput
			
	

		}
		else # Probleme avec les portgroups 
		{
			write-host -foregroundcolor RED "$($TMPVMs.name) : ERROR: Issue with PortGroup"
		}
	}
	else
	{
		
		write-host -foregroundcolor yellow "$($TMPVMs.name) a ete deja migree"
		$vm = Get-VM $TMPVMs.name
		$CurrentvCenter = $vm.Uid.Split(":")[0].Split("@")[1]
		$DC = (get-vm $VM | get-datacenter).name
		$networkAdapter = Get-NetworkAdapter -VM $TMPVMs.name
		$Cluster = (get-vm $vm | get-cluster).name
		$destinationDatastore = (Get-VM $TMPVMs.name | Get-Datastore).name
		$onlinetest = Test-Connection -computername $TMPVMs.name-Count 1 -quiet
		 switch ($onlinetest)
			{
			 $true {$PING="OK"}
			 $false {$PING="NOK"} 
			 Default {"N/A"}
			}
		$NodeOutput  = New-Object -Type PSObject            
		$NodeOutput | Add-Member -MemberType NoteProperty -Name "Name" -value $TMPVMs.name
		$NodeOutput | Add-Member -MemberType NoteProperty -Name "Cluster" -value $Cluster
		$NodeOutput | Add-Member -MemberType NoteProperty -Name "DS" -value $destinationDatastore
		$NodeOutput | Add-Member -MemberType NoteProperty -Name "Ping" -value $Ping
		$NodeOutput | Add-Member -MemberType NoteProperty -Name "DC" -value $DC
		$NodeOutput | Add-Member -MemberType NoteProperty -Name "vCenter" -value $CurrentvCenter
		$ListVMMigree += $NodeOutput
	}
}
####################################################################################
# Disconnect
#Disconnect-VIServer -Server * -Force -Confirm:$false
$ListVMMigree |ft
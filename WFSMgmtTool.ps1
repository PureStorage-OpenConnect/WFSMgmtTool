<#
.SYNOPSIS
Menu driven options to add disks and shares to the Pure Storage file server cluster.
 
.DESCRIPTION
Use the menu to CREATE or ADD disks and shares to the Pure Storage file server cluster. AKA //RUN or WFS.
 
.EXAMPLE
 
PS C:\> .\pure-storage-admin-v2.ps1
 
.NOTES
    Author: Dean Bliss <dbliss@purestorage.com>
#>

cls
Start-transcript

## -------------------------------------------------------
function PureModules
{
write-host "PureModules Function"
## Check for PureStorage Modules ##
if (Get-Module -ListAvailable -Name PureStoragePowershellSDK) {
    Write-Host "PureStorage SDK module exists"
} else {
    Write-Host "PureStorage SDK module does not exist"
        $installSDK = Read-Host -Prompt 'Would you like to install PureStorage SDK (Y/N)'
        if ($installSDK -eq "y") {
                Write-Host "Setting the Microsoft PSGallery as a trusted repository"            
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted            
                install-module -name PureStoragePowerShellSDK
        } else { 
                $script:halt = "True"
                Write-Host "Error: PureStorage modules were not installed."
                pause
                return
        }
}
if (Get-Module -ListAvailable -Name PureStoragePowershellToolkit) {
    Write-Host "PureStorage Toolkit module exists"
} else {
    Write-Host "PureStorage Toolkit module does not exist"
        $installToolkit = Read-Host -Prompt 'Would you like to install PureStorage Toolkit (Y/N)'
        if ($installToolkit -eq "y") {
                Write-Host "Setting the Microsoft PSGallery as a trusted repository"            
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted            
                install-module -name PureStoragePowerShellToolkit
        } else { 
                $script:halt = "True"
                Write-Host "Error: PureStorage modules were not installed."
                pause
                return
        }
}
## Load Pure modules ##
import-module -name PureStoragePowerShellSDK
import-module -name PureStoragePowerShellToolkit
$puremodule = get-module -name "PureStoragePowershellSDK"
if (!$puremodule){
        $script:halt = "True"
        Write-Host "Error: Unable to import Pure Storage's powershell modules. Terminating script"
        pause
        return
}
get-module -name PureStorage*
pause
}

##--------------------------------------------------------
function ConnectPureArray
{

write-host "ConnectPureArray Function"
cls
## connect to the Pure array ##
Write-Host ""
Write-Host ""
Write-Host " Please provide the hostname and login credentials for your Pure storage array."
Do {
        $script:myArrayName = Read-Host -Prompt " Enter the Pure array's FQDN"
        $myCredential = Get-Credential
        $script:Array = New-PfaArray -EndPoint $script:myArrayName -Credentials $myCredential -HttpTimeOutInMilliSeconds 300000 -IgnoreCertificateError
        if (!$script:Array){
        Write-Host "Error: Unable to connect to the Pure array ($script:myArrayName). Try again."
        }
} while (!$script:Array)

$script:Array
pause
}

##--------------------------------------------------------
function GetClusterInfo
{
        write-host "GetClusterInfo Function"
        ## get cluster information ##
        import-module failoverclusters
        $clustermodule = get-module -name "FailoverClusters"
        if (!$clustermodule){
                $script:halt = "True"
                Write-Host "Error: Unable to import Windows Failover Cluster powershell module."
                Write-Host "Make sure you're running this script inside the Windows VM that runs on the Pure array"
                pause
                return
        }
        $script:myclustername = get-cluster
        $script:mynodes = Get-ClusterNode | select-object Name
        $script:mynode1 = [string]$script:mynodes[0].name
        $script:mynode2 = [string]$script:mynodes[1].name
        $script:myfileservername = get-clusterResource | where-object {$_.resourcetype -eq "File Server"} |select-object OwnerGroup
        ## create handle if more than one file server role ##
        if (!$script:mynodes){
                $script:halt = "True"
                Write-host "Error: Unable to get cluster configuration information. Terminating script."
                pause
                return
        }
}

##--------------------------------------------------------
function DisplayVolumes
{
    write-host " Mounted Disks:"
    write-host ""
    $vol = get-volume | where {$_.driveletter -ne $null} | select driveletter,filesystemlabel,filesystem,sizeremaining,size | sort driveletter | format-table driveletter,filesystemlabel,filesystem,@{Label="Free(GB)";Expression={"{0:N0}" -F ($_.sizeremaining/1GB)}},@{Label="%Free";Expression={"{0:P0}" -F ($_.sizeremaining/$_.size)}}
    echo $vol
    write-host " SMB Shares:"
    write-host ""
    $shares = get-smbshare | where {$_.description -eq ""} | sort path
    echo $shares | out-host
    
}

##--------------------------------------------------------
function GetAvailLetters
{
    write-host "GetAvailLetters Function"
    if ($script:halt -eq "True") {
        exit
        }  
    $localvolumes = get-volume | where {$_.driveletter -ne $Null} | select driveletter | sort driveletter
    $localalpha = @("A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z")
    foreach ($a in $localvolumes)
        {
	        $localalpha = $localalpha | where {$_ -ne $a.driveletter}
        }
    if ($localalpha -contains "B")
        {
	        $localalpha = $localalpha | where {$_ -ne "B"}
        }
    if(!$localalpha)
        {
            $script:halt = "True"	        
            Write-host "There are no more available drive letters"
	        Write-host "Cannot continue"
	        pause
	        return
        }
    if ($env:computername -eq $script:mynode1) {
            $remotevolumes = invoke-command -computername $script:mynode2 -scriptblock {get-volume | where {$_.driveletter -ne $Null} | select driveletter | sort driveletter}
        } else {
            $remotevolumes = invoke-command -computername $script:mynode1 -scriptblock {get-volume | where {$_.driveletter -ne $Null} | select driveletter | sort driveletter}
        }
    $remotealpha = @("A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z")
    foreach ($b in $remotevolumes)
        {
	        $remotealpha = $remotealpha | where {$_ -ne $b.driveletter}
        }
    if ($remotealpha -contains "B")
        {
	        $remotealpha = $remotealpha | where {$_ -ne "B"}
        }
    if(!$remotealpha)
        {
            $script:halt = "True"	        
            Write-host "There are no more available drive letters"
	        Write-host "Cannot continue"
	        pause
	        return
        }
    #### Compare local letters with remote letters to see who has the highest ####
    switch ($localalpha[0])
     { 
        "A" {$la = 1} 
        "B" {$la = 2} 
        "C" {$la = 3} 
        "D" {$la = 4} 
        "E" {$la = 5} 
        "F" {$la = 6} 
        "G" {$la = 7}
        "H" {$la = 8}
        "I" {$la = 9}
        "J" {$la = 10}
        "K" {$la = 11}
        "L" {$la = 12}
        "M" {$la = 13}
        "N" {$la = 14}
        "O" {$la = 15}
        "P" {$la = 16}
        "Q" {$la = 17}
        "R" {$la = 18}
        "S" {$la = 19}
        "T" {$la = 20}
        "U" {$la = 21}
        "V" {$la = 22}
        "W" {$la = 23}
        "X" {$la = 24}
        "Y" {$la = 25}
        "Z" {$la = 26}
        default {$la = 0}
     }
    switch ($remotealpha[0])
     { 
        "A" {$ra = 1} 
        "B" {$ra = 2} 
        "C" {$ra = 3} 
        "D" {$ra = 4} 
        "E" {$ra = 5} 
        "F" {$ra = 6} 
        "G" {$ra = 7}
        "H" {$ra = 8}
        "I" {$ra = 9}
        "J" {$ra = 10}
        "K" {$ra = 11}
        "L" {$ra = 12}
        "M" {$ra = 13}
        "N" {$ra = 14}
        "O" {$ra = 15}
        "P" {$ra = 16}
        "Q" {$ra = 17}
        "R" {$ra = 18}
        "S" {$ra = 19}
        "T" {$ra = 20}
        "U" {$ra = 21}
        "V" {$ra = 22}
        "W" {$ra = 23}
        "X" {$ra = 24}
        "Y" {$ra = 25}
        "Z" {$ra = 26}
        default {$ra = 0}
     }
    if ($la -ge $ra)
    {
        $script:assignletter = $localalpha[0]
    } else {
        $script:assignletter = $remotealpha[0]
    }
         
}

##--------------------------------------------------------
function AddNewDisk
{
    write-host "AddNewDisk Function"
        if ($script:halt -eq "True") {
        exit
        }  
        ## get inputs ##
        while (!$script:volname) {
                $script:volname = read-host -prompt "Please enter a name for the volume"
        }
        while (!$volsize) {
                [Int64][ValidateRange(1,1024)]$volsize = read-host -prompt "Please enter a size for the volume (TB)"
        }
#### start Pure array procedure ####
        ## connect to array ##
        if (!$script:array) {
                ConnectPureArray
        }
        ## check if volume name doesn't exist ##
        do {
            $volexist = $null
            $allvols = Get-PfaVolumes -array $script:array
            foreach ($v in $allvols){
                if ($v.name -eq $script:volname){
                    $volexist = "yes"}
            }
            if ($volexist -eq "yes"){
                write-host "Volume name ($script:volname) already exists."
                $script:volname = $Null
                while (!$script:volname) {
                    $script:volname = read-host -prompt "Please enter a name for the volume"
                }
            }
        } until ($volexist -ne "yes")
        write-host "You entered name: $script:volname and size: $script:volsize"

        ## create volume and add it to WFS host ##
        write-host "Creating the new volume..."
        new-pfavolume -array $script:array -volumename $script:volname -size $volsize -Unit T
        New-PfaHostVolumeConnection -array $script:array -VolumeName $script:volname -HostName '@WFS'
        $script:myvol = Get-PfaVolume -Array $script:array -Name $script:volname
#### end Pure array procedure ####
#### start Windows OS procedure ####
        ## rescan os for new volume ##
        write-host "Performing local node disk rescan..."
        "rescan" | diskpart >$null
        write-host "Performing remote node disk rescan..."
        if ($env:computername -eq $script:mynode1) {
                    invoke-command -computername $script:mynode2 -Scriptblock {"rescan" | Diskpart >$null}
        } else {
                    invoke-command -computername $script:mynode1 -Scriptblock {"rescan" | Diskpart >$null} 
        }
        $disk = get-disk | where {$_.SerialNumber -eq $script:myvol.serial}
        if (!$disk){
            $script:halt = "True"
            write-host "Error: New volume does not appear in the OS after a rescan. Terminating script."
            pause
            return
        }

        $disknumber = $disk.Number
        GetAvailLetters  ## run function to get a driveletter ##

        ## online, initialize, partition, and format the disk ##
        if($disk.isoffline -eq $true){
                Set-Disk -Number $disknumber -IsOffline $False
            }
        if($disk.isreadonly -eq $true){
                Set-Disk -Number $disknumber -IsReadOnly $False
            }
        if ($disk.PartitionStyle -ne "RAW"){
            $script:halt = "True"
            write-host "Error: Disk has already been initialized, data may already exist on the disk"
            Write-Host "Check disk number ($disknumber) manually. Terminating script."
            pause
            return
        }
        write-host "Creating new partition and formatting disk..."
        get-disk | where {$_.serialnumber -eq $script:myvol.serial} |
        Initialize-Disk -Partitionstyle GPT -Passthru |
        New-Partition -DriveLetter $script:assignletter -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel $script:volname -Confirm:$false 
        $disk = get-disk | where {$_.SerialNumber -eq $script:myvol.serial}
#### end Windows OS procedure ####
#### start cluster procedure ####
        write-host "Adding disk to the cluster..."
        $clusterdisk = Get-ClusterAvailableDisk | where-object {$_.number -eq $disknumber}
        If (!$clusterdisk){
            $script:halt = "True"
            write-host "Error: Disk (number:$disknumber) is not available to the cluster, verify it is online on one of the cluster nodes."
            pause
            return
        }
        If (!($clusterdisk.number -eq $disknumber)){
            $script:halt = "True"
            write-host "Error: Disk listed in cluster is not the same disk created in this script. Please check disk management."
            pause
            return
        }
        $clusterdisk | Add-ClusterDisk
        ## check if the driveletter auto-assigned matches available letters ##
        write-host "Adding disk to the file server resource..."
        $letter = get-volume | where {$_.filesystemlabel -eq $script:volname} | select driveletter
        if ($letter.driveletter -ne $script:assignletter){
            set-partition -driveletter $($letter.driveletter) -newdriveletter $script:assignletter
        }
        ## move disk resource into the file server role ##
        $clusterresource = "Cluster Disk $disknumber"
        Move-clusterresource -Name $clusterresource -Group $script:myfileservername.ownergroup.name
        $owner = get-clusterresource -Name $clusterresource
        If ($owner.ownergroup.name -ne $script:myfileservername.ownergroup.name){
            $script:halt = "True"
            Write-host "Unable to add disk to the cluster resource ($($script:myfileservername.ownergroup.name))."
            pause
            return
        }
        ## create the share ##
        write-host "Creating the share..."
        $localvol = get-volume | where {$_.filesystemlabel -eq $script:volname}
        $myletter = $localvol.driveletter
        $sharepath = "$myletter`:\Shares"
        New-item "$sharepath" -Type directory
        New-item "$sharepath\$script:volname" -Type directory
        New-smbShare -Name $script:volname -path "$sharepath\$script:volname" -FullAccess Everyone
        ### create check for share ###
        write-host ""
        write-host " Disk successfully added to the cluster and the share was created -- see below for details"
        write-host "     Volumename: $script:volname"
        write-host "     Drive letter: $myletter`:\"
        write-host "     Share directory: $sharepath\$script:volname"
        write-host "     File server: $($script:myfileservername.ownergroup.name)"
        write-host "     Share name: $script:volname"
        write-host "     Share path: \\$($script:myfileservername.ownergroup.name)\$script:volname"
        write-host ""
#### end cluster procedure ####
}

##--------------------------------------------------------
function CloneVol
{
        cls
        write-host "CloneVol Function"
        if ($script:halt -eq "True") {
            exit
        }
        $purehosts = get-pfahosts -array $script:array
        write-host " List of existing hosts that have SAN access"
        echo $purehosts | where {$_.name -ne '@WFS'} | select name,hgroup | out-host
          
        ## get non-cluster node - reguired to change disk GUID ##
        ## create selection of node by listing Pure hosts ##
        do {
            write-host "In order to mount a cloned cluster disk, the disk unique GUID must be changed."
            write-host "Requires a non-clustered node to mount the disk, change the GUID, and then mount it back to the clustered node."
            write-host "** Important: new node must have SAN connectivity to the Pure array (either FC or iSCSI) **"
            write-host "You must provide the server hostname FQDN, and its corresponding name on the Pure array"
            while (!$nonhostname) {
                    $nonhostname = read-host -prompt "Please enter the FQDN hostname"
            }
            while (!$nonpurehost) {
                    $nonpurehost = read-host -prompt "Please enter the corresponding host listed in Pure array"
            }
        ## test connectivity to non-node ##
            if (Test-WSMan -ComputerName $nonhostname -ErrorAction Ignore){
                $connectiontest = "passed"
            }else{
                $connectiontest = "failed"
                write-host "Error: Unable to connect to host ($nonhostname). Try again..."
                $nonhostname = $Null
                $nonpurehost = $Null
                pause
            }
        } until ($connectiontest -eq "passed")
        ## check pure for hostname by FQDN or shortname ##
        $purehosts = get-pfahosts -array $script:array
        $hostexist = $Null
        foreach ($h in $purehosts){
            if($h.name -eq $nonpurehost){
                $hostexist = "yes"
            }
        }
        if($hostexist -ne "yes"){
            $script:halt -eq "True"
            write-host "Hostname you entered ($nonpurehost) does not exist as a host in the Pure array ($script:myarrayname)."
            write-host "Host must have SAN connectivity in order to mount the disk and change the GUID."
            write-host "Terminating script."
            pause
            return
        }

        ## select a clustered volume to clone ##
        $shares = get-smbshare | where {!$_.Description} | select name,scopename,path | sort path
        $global:i = 0
        $shares | select @{Name="Item";e={$global:i++;$global:i}},name,scopename,path -OutVariable menu | ft -AutoSize
        $sharescount = [int]$shares.count
        do {
             [int]$selection = read-host -prompt "Select a current volume to clone (by Item #)"
        } until ($selection -le $sharescount -and $selection -ne 0) 
        write-host "Getting volume name and drive letter..."
        $selshare = $menu | where {$_.item -eq $selection}
        $seldrive = $selshare.path[0]
        $seldisk = Get-Partition -DriveLetter $seldrive | get-disk
        $selpurevol = Get-PfaVolumes -array $script:array | where {$_.serial -eq $seldisk.SerialNumber}
        ## snapshot the selected pure volume ##
        write-host "Taking array based snapshot..."
        $timestamp = Get-Date -Format o | foreach {$_ -replace ":", "-"}
        $suffix = $timestamp.substring(0,19)
        New-PfaVolumeSnapshots -array $script:array -Sources $selpurevol.name -Suffix $suffix
        $snap = $selpurevol.name+"."+$suffix
        ## create copy from snapshot ##
        $newvol = "copy$($selpurevol.name)"
        New-PfaVolume -array $script:array -VolumeName $newvol -Source $snap -Overwrite
        ## connect copy to non-node host ##
        write-host "Connecting new volume from snapshot to ($nonhostname)"
        New-PfaHostVolumeConnection -Array $script:array -VolumeName $newvol -HostName $nonpurehost
        
        ## run commands on non-node server ##
        write-host "Rescanning disks on remote host..."
        $purecopyvol = Get-PfaVolume -Array $script:array -Name $newvol
        Invoke-Command -ComputerName $nonhostname -ScriptBlock {"rescan" | diskpart}
        $nonnodedisks = invoke-command -ComputerName $nonhostname -ScriptBlock {get-disk}
        $puredisk = $nonnodedisks | where {$_.serialnumber -eq $purecopyvol.serial}
        $disknumber = $puredisk.number
        ## create check for MBR vs GPT disk ##
        write-host "Changing the disk GUID..."
        ## online disk and change GUID ##
        if($puredisk.isoffline){
            invoke-command -ComputerName $nonhostname -ScriptBlock { param($rdisknumber,$rfalse) Set-disk -Number $rdisknumber -IsOffline $rfalse} -ArgumentList $disknumber,$false
        }
        $nonnodedisks = invoke-command -ComputerName $nonhostname -ScriptBlock {get-disk}
        $puredisk = $nonnodedisks | where {$_.serialnumber -eq $purecopyvol.serial}
        if($puredisk.isreadonly){
            invoke-command -ComputerName $nonhostname -ScriptBlock { param($rdisknumber,$rfalse) Set-disk -Number $rdisknumber -IsReadOnly $rfalse} -ArgumentList $disknumber,$false
        }
        ## get new guid and change disk guid ##
        $newguid = [guid]::NewGuid()
        $newguidtext = "{$($newguid.guid)}"
        invoke-command -ComputerName $nonhostname -ScriptBlock { param($rdisknumber,$rnewguidtext) Set-disk -Number $rdisknumber -Guid $rnewguidtext} -ArgumentList $disknumber,$newguidtext
        $nonnodedisks = invoke-command -ComputerName $nonhostname -ScriptBlock {get-disk}
        $puredisk = $nonnodedisks | where {$_.serialnumber -eq $purecopyvol.serial}
        if($puredisk.guid -ne $newguidtext){
            write-host "Error: Unable to change the disk GUID on node ($nonhostname)."
            ## remove disk from host ##
            pause
            return
        }
        ## create code - change partition GUId and possibly volume GUID ##


        ## remove disk from host and mount on cluster node ##
        write-host "Dismounting volume on remote host and mounting back to the cluster node..."
        invoke-command -ComputerName $nonhostname -ScriptBlock { param($rdisknumber,$rtrue) Set-disk -Number $rdisknumber -IsOffline $rtrue} -ArgumentList $disknumber,$true
        Remove-PfaHostVolumeConnection -Array $script:array -VolumeName $newvol -HostName $nonpurehost
        Invoke-Command -ComputerName $nonhostname -ScriptBlock {"rescan" | diskpart}
        New-PfaHostVolumeConnection -Array $script:array -VolumeName $newvol -HostName '@WFS'
        "rescan" | diskpart
        $localdisk = get-disk | where {$_.SerialNumber -eq $purecopyvol.serial}
        $localdisknumber = $localdisk.Number
        if($localdisk.isoffline){
           Set-disk -Number $localdisknumber -IsOffline $false
        }
        $localdisk = get-disk | where {$_.SerialNumber -eq $purecopyvol.serial}
        if($localdisk.isreadonly){
            Set-disk -Number $localdisknumber -IsReadOnly $false
        }
        echo $localdisk
        write-host "Disk has been successfully mounted to the cluster node, check disk management to confirm."
        pause
}

##--------------------------------------------------------
function Show-Menu
{
     param (
           [string]$Title = 'Pure Storage WFS Admin'
     )
     cls
     Write-host ""
     Write-host ""     
     Write-Host "================ $Title ================"
     Write-host ""
     Write-Host " 1: List All cluster Disks and Volumes"
     Write-Host " 2: Add a NEW Pure volume, disk, and share to the cluster"
     Write-Host " 3: Clone a Pure volume and add it to the cluster"
     Write-Host " Q: Quit"
     Write-Host ""
}

##### Script Starts Here #####
PureModules
do
{
     if (!$script:array){
        ConnectPureArray
     }
     if (!$script:myclustername){
        GetClusterInfo
     }
     if ($script:halt -eq "True") {
        Write-host "There was an error running this script - please review the log."
        Write-host "Terminating script"
        pause
        Stop-Transcript
        exit
     }  
     Show-Menu
     $input = Read-Host "Please make a selection"
     switch ($input)
     {
           '1' {
                DisplayVolumes

           } '2' {
                $script:IsNewDisk = "Yes"
                $script:volname = $Null
                if($script:volsize){
                    remove-variable volsize
                }
                AddNewDisk

           } '3' {
                CloneVol
           } 'q' {
                return
           }
     }
     pause
}
until ($input -eq 'q')
Stop-Transcript

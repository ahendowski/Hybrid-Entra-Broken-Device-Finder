function Get-ADEI {
    <#
	.SYNOPSIS
		Script to help determine broken machines in a Hybrid Environment.

	.DESCRIPTION
		ADEI stands for Active Directory Entra Intune.

        This script helps break up all objects and does different comparisons to figure out what devices are actually broken and where.

        If you are struggling on knowing which devices are in Entra but not Intune, or what devices are somehow in Intune, but not Entra, or even Intune but not AD, this tool will lay it out and allow you to filter through and find every different instance.

        The devices are added into locally stored Variables with time stamps, so when you're working out the logic on filtering, it's quick to do queries and parsing, and it helps with not having to call MSGraph and load all objects.

        When you're troubleshooting different small variations, speed is key!

	.PARAMETER  Update
		Runs the update.  Grabs all AD / Entra / Intune devices and puts them into their own

	.PARAMETER  OU
		OU allows you to set what OU you want to run the Get-ADComputer portion of the script.  If this is left blank, it'll just grab the base default, which you probably don't want.  
        Setting OU to whatever the top level folder of all your user devices, as opposed to servers, is highly recommended.
        
	.PARAMETER  Computer
		Checks a single computer if it exists in AD, Entra, and Intune.  Quick way to test a single PC without filtering.

	.PARAMETER  help
		A built in helper to find out how to use the program.  Nicely color coded!

	.EXAMPLE
        Get-ADEI -Update
        Get-ADEI -Update -OU "OU=UserAccounts,DC=your,DC=Domain"
        Get-ADEI
        Get-ADEI -Export "C:\Folder"
        Get-ADEI -help
        Get-ADEI -Computer "PC12345"
        $ADDevices | where-object {$_.Entra -eq $false -and $_.Intune -eq False}
        $EntraDevices | where-object {$_.Intune -eq $false} | select-object Displayname, DeviceID

		
	.NOTES
		Please run [Get-ADEI -Update -OU "OUPATHHERE"] before running any of the queries below.
        Note: The [-OU "OUPATHHERE"] parameter is optional, but recommended.

        Please take time to go into the powershell script and edit the [$ADFilter / $Entrafilter / $Intunefilter] before starting.
        The filter has instructions in the array as a comment to help you filter properly.

        To get more data, such as Names, Devices, Dates, TrustType, and more, please use one of the following variables:
        $ADDevices
        $EntraDevices
        $EntraDevicesBroken
        $IntuneDevices

        Each object has a property of AD, Entra, and Intune, each set to $true or $false.
        You can filter each of them out to see which object is in what category. For example:

        This will show you all Active Directory devices not in Entra AND Intune:
        $ADDevices | where-object {$_.Entra -eq $false -and $_.Intune -eq False}

        Incase there are 2 Entra objects, one working, one stale, this premade variable will showcase only objects that don't have a working duplicate:
        $EntraDevicesBroken

        For example if PC123 is in Entra twice, one working, one not working, it won't be in $EntraDevicesBroken, to prevent accidently working on a working Intune object.

#>
    [CmdletBinding()]
    param (
        # Gathering Information
        [switch]$Update,
        [String]$OU = $null,
        [switch]$help,
        [string]$export,
        [String]$Computer = $null


    )

    # Set filtering variables

    <# EXAMPLES FOR FILTERING: 
    
    Use Regular expression (regex) to be able to filter out specific naming conventions.

    AD, Entra, and Intune all use different property names for their name:

        AD = name
        Entra = Displayname
        Intune = Devicename

    I set this up because if you have a broken environment, you might have personal devices mixing in with the results.  With this, you can be sure you're filtering anything that matches your company's naming convention.

    Look up how to write Regex if you're not sure - it's not terribly complicated once you figure it out.  A very valuable resource I used as of this writing is www.regex101.com (no affiliate)

    Here's an example for Entra:
    Filtering computer names that start with a prefix followed by numbers 4 numbers, and then anything else. 
    For example: [MATH12345, ENG55933, SCI22223W, SCI334344L]

    $intunefilter = {
        (
            $_.displayname -match "^(?:MATH[A-Z]*)\d{4,}.*$" -or
            $_.displayname -match "^(?:ENG[A-Z]*)\d{4,}.*$" -or
            $_.displayname -match "^(?:SCI[A-Z]*)\d{4,}.*$"
        )
    }

    Filtering only computers that have "TrustType" ServerAD, and operating system is Windows:
        (
            $_.TrustType -eq "ServerAD" -and `
            $_.OperatingSystem -eq "Windows" `
        )

    Common troubleshooting filter properties:
        TrustType
        IsCompliant
        DisplayName
        ApproximateLastSignInDateTime
    #>

    $global:ADfilter = {
        
    }

    $global:entrafilter = {
      
    }

    $global:intunefilter = {
       
    }


    # Checks for MS Graph Connection, if none, starts the authorization.
    function Set-MSGraphConnection {
        try {
            $context = Get-MgContext -ErrorAction Stop
            if ($null -eq $context -or $null -eq $context.Account) {
                Write-Host "Not connected to MGGraph." -ForegroundColor Yellow
                Write-Host "Connecting to MGGraph..." -foregroundcolor Cyan
                Connect-MgGraph -Scopes "Device.Read.All" -NoWelcome
                $context = Get-MgContext -ErrorAction Stop

                if ($null -eq $context -or $null -eq $context.Account) {
                    throw "Could not connect to Microsoft Graph."                }
            }

            # Successful MS Graph Connection
            Write-Host "Connected to Microsoft Graph as: " -foregroundcolor Green -nonewline
            Write-Host "$($context.Account)" -ForegroundColor Magenta
        }
        catch {
            Write-Host "Error: $_" -ForegroundColor Red
            Write-Host "Please run the following command:`nConnect-MgGraph -Scopes `"Device.Read.All`"" -ForegroundColor Yellow
            return
        }
    }

    # Sets $ADDevices / $EntraDevices / $IntuneDevices
    function Update-Devices {
        Write-host "Retrieving Active Directory Computer Objects..." -ForegroundColor Cyan
        if (!$OU) {
            Write-host "-OU not set.  Searching entire Active Directory." -ForegroundColor Yellow
            $Global:ADDevices = Get-ADComputer -Filter * -Properties *
        } else {
            Write-host "TargetOU: " -NoNewline -ForegroundColor Cyan
            Write-host "$OU" -ForegroundColor Yellow
            $Global:ADDevices = Get-ADComputer -Filter * -Properties * -SearchBase $OU
        }
        Write-Host "`$ADDevices" -foregroundcolor white -BackgroundColor DarkBlue -nonewline
        write-host " updated!" -ForegroundColor Green

        Write-Host "Retrieving Entra devices..." -ForegroundColor Cyan
        $Global:EntraDevices = Get-MGDevice -All | Where-Object { $_.OperatingSystem -eq "Windows" }
        Write-Host "`$EntraDevices" -foregroundcolor white -BackgroundColor DarkBlue -nonewline
        Write-host " updated!" -ForegroundColor Green

        Write-Host "Retrieving Intune Objects..." -ForegroundColor Cyan
        $Global:IntuneDevices = Get-MGDeviceManagementManagedDevice -All
        Write-Host "`$IntuneDevices" -foregroundcolor white -BackgroundColor DarkBlue -nonewline
        Write-host " updated!" -ForegroundColor Green

        $Global:SyncTime = Get-Date

    }
        

    # 1. Main function that creates properties [AD, Entra, Intune] for [$ADDevices, $EntraDevices, $IntuneDevices]
        # The reason for the local variable is to be able to call $ADDevices easily without having to constantly connect to MSGraph / call AD.  This is good for troubleshooting speed as it's all loaded in memory.
    # 2. Checks what matches between all variables, and if it matches sets the flag to $true, otherwise by default it's set to $false
    # 3. Creates $EntraDevicesBroken to remove any duplicates to avoid listing machines that are working.  More explained in the help file.
    # 4. Lists out how many machines are broken so you know what kind of situation you're in.
    function Compare-ADEI {
        $global:EntraDevicesBroken = @()

        $ADDevices | add-member -notepropertyname "AD" -notepropertyvalue $true -force
        $ADDevices | add-member -notepropertyname "Entra" -notepropertyvalue $false -force
        $ADDevices | add-member -notepropertyname "Intune" -notepropertyvalue $false -force

        $EntraDevices | add-member -notepropertyname "AD" -notepropertyvalue $false -force
        $EntraDevices | add-member -notepropertyname "Entra" -notepropertyvalue $true -force
        $EntraDevices | add-member -notepropertyname "Intune" -notepropertyvalue $false -force

        $IntuneDevices | add-member -notepropertyname "AD" -notepropertyvalue $false -force
        $IntuneDevices | add-member -notepropertyname "Entra" -notepropertyvalue $false -force
        $IntuneDevices | add-member -notepropertyname "Intune" -notepropertyvalue $true -force

        
            # Initialize progress bar
        $totalCount = $ADDevices.Count
        $counter = 0

        # Check AD for Entra
        foreach ($ADDevice in $ADDevices) {
            $EntraDeviceMatchAD = $EntraDevices | where-object $entrafilter | Where-Object { $_.DisplayName -eq $ADDevice.Name }

            # Check Entra Device ID for matching Intune Device ID
            if ($EntraDeviceMatchAD) {
                $ADDevice.Entra = $true
                
                # If $ADMatchEntra has 2 objects (duplicates in Entra), then check for each of them
                foreach ($EntraMatch in $EntraDeviceMatchAD) {
                    
                    $EntraMatch.AD = $true
                    $IntuneDeviceMatchEntra = $IntuneDevices | where-object { $_.AzureADDeviceID -eq $EntraMatch.DeviceID }

                    if ($IntuneDeviceMatchEntra) {
                        $ADDevice.Intune = $true
                        $EntraMatch.Intune = $true
                        $IntuneDeviceMatchEntra.Entra = $true
                        $IntuneDeviceMatchEntra.AD = $true
                        break
                    }
                }
                
        }

                # Update progress bar
                $counter++
                Write-Progress -Activity "Getting data for AD, Entra, Intune" `
                -Status "Processing device $counter of $totalCount" `
                -PercentComplete (($counter / $totalCount) * 100)

    }


    $entraDevicesByDisplayName = $EntraDevices | Group-Object -Property DisplayName

    foreach ($group in $entraDevicesByDisplayName) {
        # Check if there's any Intune = $true within this group
        $hasIntuneEntry = $group.Group | Where-Object { $_.Intune -eq $true }

        # If no entry in the group has Intune = $true, add all entries with Intune = $false to the result list
        if (-not $hasIntuneEntry) {
            $global:EntraDevicesBroken += $group.Group | Where-Object { $_.Intune -eq $false }
        }
    }
        
            Write-Progress -PercentComplete 100 -Activity "Comparison Complete" -Status "All devices processed"

    }

    # Checks each computer if it exists or is missing from AD, Entra, or Intune to quickly see where something is broken.
    function Get-ADEISingle {
        Param ([String]$ComputerName
        )

        $ADComputerGet = $null
        $EntraComputerGet = $null
        $IntuneComputerGet = $null

        $ADComputerGet = ($ADDevices | Where-Object name -eq "$ComputerName")
        $EntraComputerGet = ($EntraDevices | Where-Object DisplayName -eq "$ComputerName")
        $IntuneComputerGet = ($IntuneDevices | Where-Object DeviceName -eq "$ComputerName")

        if ($null -eq $ADComputerGet -and $null -eq $EntraComputerGet -and $null -eq $IntuneComputerGet) {
            write-host "Error: No computer exists by the name of $ComputerName." -ForegroundColor Red
            return
        }

        Write-host "Checking for $ComputerName`:" -ForegroundColor Magenta
        if ($null -eq $ADComputerGet) {
            Write-Host "AD:`t" -NoNewline -ForegroundColor Yellow
            Write-Host "NO" -ForegroundColor Red
        } else {
            Write-Host "AD:`t" -NoNewline -ForegroundColor Yellow
            Write-Host "YES" -ForegroundColor Green
        }

        if ($null -eq $EntraComputerget) {
            Write-Host "Entra:`t" -NoNewline -ForegroundColor Cyan
            Write-Host "NO" -ForegroundColor Red
        } else {
            Write-Host "Entra:`t" -NoNewline -ForegroundColor Cyan
            Write-Host "YES" -ForegroundColor Green
        }

        if ($null -eq $IntuneComputerGet) {
            Write-Host "Intune:`t" -NoNewline -ForegroundColor Gray
            Write-Host "NO" -ForegroundColor Red
        } else {
            Write-Host "Intune:`t" -NoNewline -ForegroundColor Gray
            Write-Host "YES" -ForegroundColor Green
        }
        
    }

    function Get-ADEIHelp {
        write-host "******`n******" -ForegroundColor Magenta
        write-host "Please run [" -NoNewline
        write-host "Get-ADEI -Update -OU `"OUPATHHERE`"" -NoNewline -ForegroundColor Yellow
        write-host "] before running any of the queries below.`nNote: The [" -nonewline 
        write-host "-OU `"OUPATHHERE`"" -nonewline -ForegroundColor Yellow
        write-host "] parameter is optional, but highly recommended.`n" 

        write-host "Please take time to go into the powershell script and edit the [" -nonewline 
        write-host "`$ADFilter / `$Entrafilter / `$Intunefilter" -NoNewline -ForegroundColor Yellow
        write-host "] before starting." 
        write-host "The filter has instructions (in the comment above it at the top of all the code) to help you filter properly.`n" 

        write-host "To get more data, such as Names, Devices, Dates, Trust Type, and more, please use one of the following variables:" 
        write-host "`$ADDevices" -ForegroundColor Yellow
        write-host "`$EntraDevices`n`$EntraDevicesBroken" -ForegroundColor Cyan
        write-host "`$IntuneDevices" -ForegroundColor Green
        write-host ""
        write-host "Each object has a property of AD, Entra, and Intune, each set to " -nonewline 
        write-host "`$true" -ForegroundColor Green -nonewline
        write-host " or " -nonewline 
        write-host "`$false." -nonewline -ForegroundColor red
        write-host "`nYou can filter each of them out to see which object is in what category. For example:`n" 
        write-host "This will show you all Active Directory devices not in Entra AND Intune:" 
        write-host "`$ADDevices | where-object {`$_.Entra -eq `$false -and `$_.Intune -eq False}`n" -ForegroundColor Yellow

        write-host "Incase there are 2 Entra objects, one working in Intune, one stale, this premade variable will showcase only objects that don't have a working Intune duplicate:" 
        write-host "`$EntraDevicesBroken`n" -ForegroundColor Cyan
        write-host "For example if PC123 is in Entra twice, one connected to Intune, and one stale, it won't be in `$EntraDevicesBroken, to prevent accidently working on a working Intune object."
        write-host "`$EntraDevicesBroken is probably your best bet to get a big list of all computers that are in Entra, but not working properly in Intune." 
        write-host "******`n******" -ForegroundColor Magenta
    }

    function Export-ADEIReport {
        # Checks to see if the export filepath has a '\' at the end of it.  If it does not, add it.
        # C:\folder = C:\folder\

        try {
            get-childitem -path $export -erroraction stop | out-null
        } catch {
            write-host "The path [$export] does not exist.  Please enter a correct path." -ForegroundColor red
            return
            }
        
        if ($export[-1] -ne '\') { 
            $export = "$export\" 
        }
        

        $ADDevices | export-csv -path "${export}ADDevices.csv" -Verbose -notypeinformation
        $EntraDevices | export-csv -path "${export}EntraDevices.csv" -Verbose -NoTypeInformation
        $EntraDevicesBroken | export-csv -path "${export}EntraDevicesBroken.csv" -Verbose -NoTypeInformation
        $IntuneDevices | export-csv -path "${export}IntuneDevices.csv" -Verbose -NoTypeInformation
        return

    }

    function Get-ADEIReport {
        Write-host "************************" -ForegroundColor yellow
        write-host "Broken devices report:"
        Write-host "************************" -ForegroundColor Yellow

        Write-host "Last Sync Time: " -foregroundcolor Green -NoNewline
        Write-Host "$($Global:ADDate.tostring("MM/dd/yy hh:mm tt"))" -foregroundcolor Magenta
        Write-Host ""

        write-host "Total " -nonewline -ForegroundColor Magenta
        write-host "AD " -nonewline -ForegroundColor yellow
        write-host "Devices: " -ForegroundColor Magenta -nonewline
        write-host "$($ADDevices.count)" 

        write-host "Total " -nonewline -ForegroundColor Magenta
        write-host "Entra " -nonewline -ForegroundColor Cyan
        write-host "Devices: " -ForegroundColor Magenta -nonewline
        write-host "$($EntraDevices.count)" 

        write-host "Total " -nonewline -ForegroundColor Magenta
        write-host "Intune " -nonewline -ForegroundColor Green
        write-host "Devices: " -ForegroundColor Magenta -nonewline
        write-host "$($IntuneDevices.count)" 

        write-host ""
        
        Write-Host "In " -nonewline
        write-host "AD" -ForegroundColor Yellow -nonewline
        write-host " | NOT " -nonewline 
        write-host "Entra" -nonewline -ForegroundColor Cyan
        write-host ": " -nonewline
        write-host "$($ADDevices | where-object $adfilter | where-object {$_.Entra -eq $false} | measure-object | select-object -ExpandProperty Count)" -ForegroundColor Red

        Write-Host "In " -nonewline
        write-host "AD" -ForegroundColor Yellow -nonewline
        write-host " | NOT " -nonewline 
        write-host "Intune" -nonewline -ForegroundColor Green
        write-host ": " -nonewline
        write-host "$($ADDevices | where-object $adfilter | where-object {$_.Intune -eq $false} | measure-object | select-object -ExpandProperty Count)" -ForegroundColor red
        write-host ""

        Write-Host "In " -nonewline
        write-host "Entra" -ForegroundColor Cyan -nonewline
        write-host " | NOT " -nonewline 
        write-host "AD" -nonewline -ForegroundColor Yellow
        write-host ": " -nonewline
        write-host "$($EntraDevices | where-object $entrafilter | where-object {$_.AD -eq $false} | measure-object | select-object -ExpandProperty Count)" -ForegroundColor red

        Write-Host "In " -nonewline
        write-host "Entra" -ForegroundColor cyan -nonewline
        write-host " | NOT " -nonewline 
        write-host "Intune" -nonewline -ForegroundColor Green
        write-host ": " -nonewline
        write-host "$($EntraDevicesBroken | where-object $entrafilter | measure-object | select-object -ExpandProperty Count)" -ForegroundColor red
        write-host ""

        Write-Host "In " -nonewline
        write-host "Intune" -ForegroundColor Green -nonewline
        write-host " | NOT " -nonewline 
        write-host "AD" -nonewline -ForegroundColor Yellow
        write-host ": " -nonewline
        write-host "$($IntuneDevices | where-object $intunefilter | where-object {$_.AD -eq $false} | measure-object | select-object -ExpandProperty Count)" -ForegroundColor red

        Write-Host "In " -nonewline
        write-host "Intune" -ForegroundColor Green -nonewline
        write-host " | NOT " -nonewline 
        write-host "Entra" -nonewline -ForegroundColor Cyan
        write-host ": " -nonewline
        write-host "$($IntuneDevices | where-object $intunefilter | where-object {$_.Entra -eq $false} | measure-object | select-object -ExpandProperty Count)" -ForegroundColor red
        write-host ""
    }


    if ($help) {
        Get-ADEIHelp
        return
    }


    if ($Update) {
        $measuredtime = measure-command {
            write-host "Start time:"$(Get-Date -format "MM/dd/yyyy @ hh:mm:ss tt") -foregroundcolor Yellow
            Set-MSGraphConnection
            Update-Devices
            Compare-ADEI
            Get-ADEIReport
            write-host "End time:"$(Get-Date -format "MM/dd/yyyy @ hh:mm:ss tt") -foregroundcolor Yellow
    }
    write-host ("Total time ran: {0:D2}:{1:D2}:{2:D2}" -f $measuredtime.Hours, $measuredtime.Minutes, $measuredtime.Seconds) -foregroundcolor yellow
        return
    }


    # If Sync Time never ran, then error out.
    if ($null -eq $SyncTime) {
        write-host "Error: No data. Please run [" -ForegroundColor red -nonewline
        write-host "Get-ADEI -Update -OU `"OUPATHHERE`"" -nonewline
        write-host "] first." -ForegroundColor red
        return
    }

    if ($export) {
        Export-ADEIReport
        return
    }

    if ($Computer) {
        Get-ADEISingle -ComputerName $Computer
        return 
        }

    Get-ADEIReport
}


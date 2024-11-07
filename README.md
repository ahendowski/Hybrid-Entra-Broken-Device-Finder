# Hybrid-Entra-Broken-Device-Finder
---
## DESCRIPTION
A PowerShell function that helps you check what devices are broken, and where, in a Hybrid environment by comparing Active Directory, Entra, and Intune and displaying filterable information.

---
***ADEI*** stands for **A**ctive **D**irectory **E**ntra **I**ntune.

This script helps break up all objects and does different comparisons to figure out what devices are actually broken and where.

If you are struggling on knowing which devices are in Entra but not Intune, or what devices are somehow in Intune, but not Entra, or even Intune but not AD, this tool will lay it out and allow you to filter through and find every different instance.

The devices are added into locally stored Variables with time stamps, so when you're working out the logic on filtering, it's quick to do queries and parsing, and it helps with not having to call MSGraph and load all objects.

When you're troubleshooting different small variations, speed is key!

---
# Basic Usage
Start by changing the $adfilter / $entrafilter / $intunefilter to match any syntax utilizing regex.  I added an entire comment in the .ps1 file to explain how to go about creating a filter for your own environment. 

To use the script, please run [***Get-ADEI -Update -OU "OU=UserAccounts,DC=your,DC=Domain"***] to get all your information first.  This will require Microsoft Graph and will automatically connect you to Device.Read.All, make sure you have authorization to connect!

Once complete, you'll have 4 variables to run your own filtering on:
- $ADDevices
- $EntraDevices
- $EntraDevicesBroken
- $IntuneDevices

Each variable gets it's own properties added - [AD / Entra / Intune].

---
## Example filtering
This will show you all Active Directory devices not in Entra AND Intune:
```
$ADDevices | where-object {$_.Entra -eq $false -and $_.Intune -eq False}
```

Incase there are 2 Entra objects, one working, one stale, this premade variable will showcase only objects that don't have a working duplicate:
*For example if PC123 is in Entra twice, one working, one not working, it won't be in $EntraDevicesBroken, to prevent accidentally working on a working Intune object.*
```
$EntraDevicesBroken
```

Shows all devices that are in Intune, but have no AD object associated with them:
```
$IntuneDevices | where-object {$_.AD -eq $false} | select-object Displayname, DeviceID
```
***For more information, please reference the Get-Help file included in Get-ADEI***


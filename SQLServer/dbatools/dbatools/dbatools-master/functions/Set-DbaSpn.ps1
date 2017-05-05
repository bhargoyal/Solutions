#ValidationTags#FlowControl,Pipeline#
Function Set-DbaSpn
{
<#
.SYNOPSIS
Sets an SPN for a given service account in active directory (and also enables delegation to the same SPN by default)

.DESCRIPTION
This function will connect to Active Directory and search for an account. If the account is found, it will attempt to add an SPN. Once the SPN
is added, the function will also set delegation to that service, unless -NoDelegation is specified. In order to run this function, the credential you provide must have write
access to Active Directory.

Note: This function supports -WhatIf

.PARAMETER SPN
The SPN you want to add

.PARAMETER ServiceAccount
The account you want the SPN added to

.PARAMETER Credential
The credential you want to use to connect to Active Directory to make the changes

.PARAMETER NoDelegation
Skips setting the delegation

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.PARAMETER Confirm
Turns confirmations before changes on or off

.PARAMETER WhatIf
Shows what would happen if the command was executed	

.NOTES
Tags: SPN
Author: Drew Furgiuele (@pittfurg), http://www.port1433.com

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Set-DbaSpn

.EXAMPLE
Set-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account

Connects to Active Directory and adds a provided SPN to the given account.

Set-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account -Silent

Connects to Active Directory and adds a provided SPN to the given account, suppressing all error messages and throw exceptions that can be caught instead

.EXAMPLE
Set-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account -Credential (Get-Credential)

Connects to Active Directory and adds a provided SPN to the given account. Uses alternative account to connect to AD.

.EXAMPLE
Set-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account -NoDelegation

Connects to Active Directory and adds a provided SPN to the given account, without the delegation.

.EXAMPLE
Test-DbaSpn -ComputerName sql2016 | Where { $_.isSet -eq $false } | Set-DbaSpn

Sets all missing SPNs for sql2016

.EXAMPLE
Test-DbaSpn -ComputerName sql2016 | Where { $_.isSet -eq $false } | Set-DbaSpn -WhatIf

Displays what would happen trying to set all missing SPNs for sql2016

#>
	[cmdletbinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
	param (
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
		[Alias("RequiredSPN")]
		[string]$SPN,
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
		[Alias("InstanceServiceAccount", "AccountName")]
		[string]$ServiceAccount,
		[Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
		[pscredential]$Credential,
		[switch]$NoDelegation,
		[switch]$Silent
	)
	
	process
	{
		
		#did we find the server account?
		Write-Message -Message "Looking for account $ServiceAccount..." -Level Verbose
		try
		{
			$Result = Get-DbaADObject -ADObject $ServiceAccount -Type User -Credential $Credential -Silent
		}
		catch
		{
			Stop-Function -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($ServiceAccount). $($_.Exception.Message)" -Silent $Silent -InnerErrorRecord $_ -Target $ServiceAccount
		}
		if ($Result.Count -gt 0)
		{
			try {
				$adentry = $Result.GetUnderlyingObject()
			} catch {
				Stop-Function -Message "The SQL Service account ($ServiceAccount) has been found, but you don't have enough permission to inspect its properties $($_.Exception.Message)" -Silent $Silent -InnerErrorRecord $_ -Target $ServiceAccount
			}
		} else {
			Stop-Function -Message "The SQL Service account ($ServiceAccount) has not been found" -Silent $Silent -Target $ServiceAccount
		}
		# Cool! Add an SPN
		$delegate = $true
		if ($PSCmdlet.ShouldProcess("$spn", "Adding SPN to service account"))
		{
			try
			{
				$null = $adentry.Properties['serviceprincipalname'].Add($spn)
				$status = "Successfully added SPN"
				$adentry.CommitChanges()
				Write-Message -Message "Added SPN $spn to $ServiceAccount" -Level Verbose
				$set = $true
			}
			catch
			{
				Write-Message -Message "Could not add SPN. $($_.Exception.Message)" -Level Warning -Silent $Silent -ErrorRecord $_ -Target $ServiceAccount
				$set = $false
				$status = "Failed to add SPN"
				$delegate = $false
			}
			
			[pscustomobject]@{
				Name = $spn
				ServiceAccount = $ServiceAccount
				Property = "servicePrincipalName"
				IsSet = $set
				Notes = $status
			}
		}
		
		#if we have the SPN set, we can add the delegation
		if ($delegate) {
			# but only if $NoDelegation is not passed
			if(!$NoDelegation) {
				if ($PSCmdlet.ShouldProcess("$spn", "Adding constrained delegation to service account for SPN"))
				{
					try
					{
						$null = $adentry.Properties['msDS-AllowedToDelegateTo'].Add($spn)
						$adentry.CommitChanges()
						Write-Message -Message "Added kerberos delegation to $spn for $ServiceAccount" -Level Verbose
						$set = $true
						$status = "Successfully added constrained delegation"
					}
					catch
					{
						Write-Message -Message "Could not add delegation. $($_.Exception.Message)" -Level Warning -Silent $Silent -ErrorRecord $_ -Target $ServiceAccount
						$set = $false
						$status = "Failed to add constrained delegation"
					}
					
					[pscustomobject]@{
						Name = $spn
						ServiceAccount = $ServiceAccount
						Property = "msDS-AllowedToDelegateTo"
						IsSet = $set
						Notes = $status
					}
				}
			} else {
				Write-Message -Message "Skipping delegation as instructed" -Level Verbose
			}
		}
	}
}
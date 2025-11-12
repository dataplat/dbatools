if ($PSVersionTable.PSVersion.Major -lt 5) {

    <#
    PowerShell v3-compatible version of Import-PfxCertificate
    The native Import-PfxCertificate cmdlet was introduced in PowerShell v5
    This implementation provides equivalent functionality for v3+ using .NET Framework APIs
    #>

    function Import-PfxCertificate {
        <#
            .SYNOPSIS
                Imports certificates and private keys from a PFX file to a certificate store (PowerShell v3 compatible).

            .DESCRIPTION
                Imports all certificates (including intermediate certificates) from a PFX file into the specified certificate store.
                This is a PowerShell v3-compatible implementation of the native Import-PfxCertificate cmdlet that was introduced in v5.

                Unlike the basic X509Certificate2.Import() method, this function imports the entire certificate chain,
                including intermediate certificates, which is essential for proper SSL/TLS certificate validation.

            .PARAMETER FilePath
                The path to the PFX file to import.

            .PARAMETER CertStoreLocation
                The certificate store location where certificates will be installed.
                Format: Cert:\<Store>\<Folder> (e.g., "Cert:\LocalMachine\My")

            .PARAMETER Password
                The password for the PFX file as a SecureString.

            .PARAMETER Exportable
                If specified, marks the private key as exportable.

            .NOTES
                This function is only loaded in PowerShell versions prior to v5.
                PowerShell v5+ will use the native Import-PfxCertificate cmdlet instead.

            .EXAMPLE
                $password = Read-Host "Enter password" -AsSecureString
                Import-PfxCertificate -FilePath "C:\cert\fullchain.pfx" -CertStoreLocation "Cert:\LocalMachine\My" -Password $password

                Imports all certificates from the PFX file to the LocalMachine\My store.
        #>
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string]$FilePath,

            [Parameter(Mandatory)]
            [string]$CertStoreLocation,

            [SecureString]$Password,

            [switch]$Exportable
        )

        try {
            # Parse the certificate store location
            if ($CertStoreLocation -notmatch "^Cert:\\(.+)\\(.+)$") {
                throw "Invalid CertStoreLocation format. Expected format: Cert:\<Store>\<Folder>"
            }
            $storeName = $Matches[1]
            $storeFolder = $Matches[2]

            # Verify the file exists
            if (-not (Test-Path -Path $FilePath)) {
                throw "Certificate file not found: $FilePath"
            }

            # Read the PFX file
            $certBytes = [System.IO.File]::ReadAllBytes($FilePath)

            # Set the import flags
            $importFlags = "PersistKeySet"
            if ($Exportable) {
                $importFlags += ", Exportable"
            }

            # Import all certificates from the PFX using X509Certificate2Collection
            $collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
            $collection.Import($certBytes, $Password, $importFlags)

            # Open the certificate store
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeFolder, $storeName)
            $store.Open("ReadWrite")

            # Add all certificates from the collection to the store
            foreach ($cert in $collection) {
                $store.Add($cert)
                Write-Verbose "Imported certificate: $($cert.Subject) (Thumbprint: $($cert.Thumbprint))"
            }

            # Close the store
            $store.Close()

            # Return the imported certificates
            foreach ($cert in $collection) {
                Get-ChildItem "Cert:\$storeName\$storeFolder" | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
            }

        } catch {
            throw "Failed to import PFX certificate: $($_.Exception.Message)"
        }
    }
}

# got this from here
# https://vimalshekar.github.io/scriptsamples/Getting-Stored-Windows-Credentials-using-PowerShell
Function Get-ADSConnection {

    # Defining C# code to enum credman creds
    $CredEnumWrapperClass =
    @'
using System;
using System.Runtime.InteropServices;
namespace CredEnum {
        public enum CRED_FLAGS : uint {
            NONE = 0x0,
            PROMPT_NOW = 0x2,
            USERNAME_TARGET = 0x4
        }
        public enum CRED_ERRORS : uint {
            ERROR_SUCCESS = 0x0,
            ERROR_INVALID_PARAMETER = 0x80070057,
            ERROR_INVALID_FLAGS = 0x800703EC,
            ERROR_NOT_FOUND = 0x80070490,
            ERROR_NO_SUCH_LOGON_SESSION = 0x80070520,
            ERROR_BAD_USERNAME = 0x8007089A
        }
        public enum CRED_PERSIST : uint {
            SESSION = 1,
            LOCAL_MACHINE = 2,
            ENTERPRISE = 3
        }
        public enum CRED_TYPE : uint {
            GENERIC = 1,
            DOMAIN_PASSWORD = 2,
            DOMAIN_CERTIFICATE = 3,
            DOMAIN_VISIBLE_PASSWORD = 4,
            GENERIC_CERTIFICATE = 5,
            DOMAIN_EXTENDED = 6,
            MAXIMUM = 7,
            MAXIMUM_EX = 1007
        }

        //-- [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct Credential {
            public CRED_FLAGS Flags;
            public CRED_TYPE Type;
            public string TargetName;
            public string Comment;
            public DateTime LastWritten;
            public UInt32 CredentialBlobSize;
            public string CredentialBlob;
            public CRED_PERSIST Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }
        //-- [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct NativeCredential {
            public CRED_FLAGS Flags;
            public CRED_TYPE Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public UInt32 CredentialBlobSize;
            public IntPtr CredentialBlob;
            public CRED_PERSIST Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }
    //-- For Safehandling of pointer to pointer of a non-blittable type
    public class CriticalCredentialHandle : Microsoft.Win32.SafeHandles.CriticalHandleZeroOrMinusOneIsInvalid
    {
        public CriticalCredentialHandle(IntPtr preexistingHandle)
        {
            SetHandle(preexistingHandle);
        }
        private Credential TranslateNativeCred(IntPtr pCred)
        {
            NativeCredential ncred = (NativeCredential)Marshal.PtrToStructure(pCred, typeof(NativeCredential));
            Credential cred = new Credential();
            cred.Type = ncred.Type;
            cred.Flags = ncred.Flags;
            cred.Persist = (CRED_PERSIST)ncred.Persist;
            long LastWritten = ncred.LastWritten.dwHighDateTime;
            LastWritten = (LastWritten << 32) + ncred.LastWritten.dwLowDateTime;
            cred.LastWritten = DateTime.FromFileTime(LastWritten);
            cred.UserName = ncred.UserName;
            cred.TargetName = ncred.TargetName;
            cred.TargetAlias = ncred.TargetAlias;
            cred.Comment = ncred.Comment;
            cred.CredentialBlobSize = ncred.CredentialBlobSize;

            if (0 < ncred.CredentialBlobSize)
            {
                cred.CredentialBlob = Marshal.PtrToStringUni(ncred.CredentialBlob, (int)ncred.CredentialBlobSize / 2);
            }
            return cred;
        }
        public Credential GetCredential()
        {
            if (IsInvalid)
            {
                throw new InvalidOperationException("Invalid CriticalHandle.");
            }
            Credential cred = TranslateNativeCred(handle);
            return cred;
        }
        public Credential[] GetCredentials(int count)
        {
            if (IsInvalid)
            {
                throw new InvalidOperationException("Invalid CriticalHandle.");
            }
            Credential[] Credentials = new Credential[count];
            IntPtr pTemp = IntPtr.Zero;
            for (int inx = 0; inx < count; inx++)
            {
                pTemp = Marshal.ReadIntPtr(handle, inx * IntPtr.Size);
                Credential cred = TranslateNativeCred(pTemp);
                Credentials[inx] = cred;
            }
            return Credentials;
        }
        override protected bool ReleaseHandle()
        {
            if (IsInvalid)
            {
                return false;
            }
            //CredFree(handle);
            SetHandleAsInvalid();
            return true;
        }
    }
    //-- wrapper for CredEnumerate() winAPI
    public class CredEnumerator {
        //-- Defining some of the types we will use for this code
        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredEnumerate")]
        public static extern bool CredEnumerate([In] string Filter, [In] int Flags, out int Count, out IntPtr CredentialPtr);
        public static Credential[] CredEnumApi(string Filter)
        {
            int count = 0;
            int Flags = 0x0;
            IntPtr pCredentials = IntPtr.Zero;
            if (string.IsNullOrEmpty(Filter) || "*" == Filter)
            {
                Filter = null;
                if (6 <= Environment.OSVersion.Version.Major)
                {
                    Flags = 0x1; //CRED_ENUMERATE_ALL_CREDENTIALS; only valid is OS >= Vista
                }
            }
            if (CredEnumerate(Filter, Flags, out count, out pCredentials))
            {
                //--allocate credentials array
                CriticalCredentialHandle CredHandle = new CriticalCredentialHandle(pCredentials);
                Credential[] Credentials = new Credential[count];

                Credentials = CredHandle.GetCredentials(count);
                for (int inx = 0; inx < count; inx++)
                {
                    Credential curr = Credentials[inx];
                }
                return Credentials;
            }
            return null;
        }
    } //-- end of public class CredEnumerator
} //-- end of namespace CredEnum
'@

    try {
        # Attempt to create an instance of this class
        Add-Type $CredEnumWrapperClass
    } catch {
        throw "unable to compile"
    }

    $results = [CredEnum.CredEnumerator]::CredEnumApi("") | Where-Object TargetName -match SqlTools
    foreach ($credentry in $results) {
        $hostname = $credentry.TargetName.ToLower()

        try {
            if ($credentry.CredentialBlob -match "^.{1,20}$") {
                $password = $credentry.CredentialBlob
            } else {
                $password = $null
            }


            if ($hostname) {
                $result = @{
                    password = $password
                }
                $connstring = ($hostname -split "profile\|id\:")[1]
                $connstring = ($connstring -split "\|")
                foreach ($section in $connstring) {
                    $id, $value = $section.Split(":")
                    $result.$id = $value
                }
                $result = [PSCustomObject]$result

                $connstring = "Data Source=$($result.server);User ID=$($result.user);Password=$($result.password)"
                $connstring += ';Application Name="dbatools PowerShell module - dbatools.io"'
                if ($result.database) {
                    $connstring += ";Initial Catalog=""$($result.database)"""
                }
                $result | Add-Member -Force -Name connectionstring -Value "$connstring" -MemberType NoteProperty -Passthru
            }
        } catch {
            $null = 1
        }
    }
}
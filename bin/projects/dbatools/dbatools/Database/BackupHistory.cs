using System;
using System.Numerics;
using Sqlcollaborative.Dbatools.Utility;

namespace Sqlcollaborative.Dbatools.Database
{
    /// <summary>
    /// Object containing the information about the history of mankind ... or a database backup. WHo knows.
    /// </summary>
    public class BackupHistory
    {
        /// <summary>
        /// The name of the computer running MSSQL Server
        /// </summary>
        public string ComputerName;

        /// <summary>
        /// The Instance that was queried
        /// </summary>
        public string InstanceName;

        /// <summary>
        /// The full Instance name as seen from outside
        /// </summary>
        public string SqlInstance;

        /// <summary>
        /// The full Instance name as seen from outside
        /// </summary>
        public string AvailabilityGroupName;

        /// <summary>
        /// The Database that was backed up
        /// </summary>
        public string Database;

        /// <summary>
        /// The user that is running the backup
        /// </summary>
        public string UserName;

        /// <summary>
        /// When was the backup started
        /// </summary>
        public DateTime Start;

        /// <summary>
        /// When did the backup end
        /// </summary>
        public DateTime End;

        /// <summary>
        /// What was the longest duration among the backups
        /// </summary>
        public DbaTimeSpan Duration;

        /// <summary>
        /// Where is the backup stored
        /// </summary>
        public string[] Path;

        /// <summary>
        /// What is the total size of the backup
        /// </summary>
        public Size TotalSize;

        /// <summary>
        /// What is the total compressesed size of the backup
        /// </summary>
        public Size CompressedBackupSize;

        /// <summary>
        /// What is the ratio of total size to compressed size of the backup
        /// </summary>
        public double CompressionRatio;

        /// <summary>
        /// The kind of backup this was
        /// </summary>
        public string Type;

        /// <summary>
        /// The ID for the Backup job
        /// </summary>
        public string BackupSetId;

        /// <summary>
        /// What kind of backup-device was the backup stored to
        /// </summary>
        public string DeviceType;

        /// <summary>
        /// What is the name of the backup software?
        /// </summary>
        public string Software;

        /// <summary>
        /// The full name of the backup
        /// </summary>
        public string[] FullName;

        /// <summary>
        /// The files that are part of this backup
        /// </summary>
        public object FileList;

        /// <summary>
        /// The position of the backup
        /// </summary>
        public int Position;

        /// <summary>
        /// The first Log Sequence Number
        /// </summary>
        public BigInteger FirstLsn;

        /// <summary>
        /// The Log Squence Number that marks the beginning of the backup
        /// </summary>
        public BigInteger DatabaseBackupLsn;

        /// <summary>
        /// The checkpoint's Log Sequence Number
        /// </summary>
        public BigInteger CheckpointLsn;

        /// <summary>
        /// The last Log Sequence Number
        /// </summary>
        public BigInteger LastLsn;

        /// <summary>
        /// The primary version number of the Sql Server
        /// </summary>
        public int SoftwareVersionMajor;

        /// <summary>
        /// Was the backup performed with the CopyOnlyOption
        /// </summary>
        public Boolean IsCopyOnly;

        /// <summary>
        /// Recovery Fork backup was takeon
        /// </summary>
        public Guid LastRecoveryForkGUID;

        /// <summary>
        /// Recovery Model of the database when backup was taken
        /// </summary>
        public string RecoveryModel;

        /// <summary>
        /// Key Algorithm used to encrypt backup
        /// </summary>
        public string KeyAlgorithm;

        /// <summary>
        /// Thumbprint of the certificate or key used to encrypt the backup
        /// </summary>
        public string EncryptorThumbprint;

        /// <summary>
        /// Type of encryptor used to encrypt backup (Key or Certificate)
        /// </summary>
        public string EncryptorType;

    }
}
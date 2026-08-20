************************************************************************
* Read every byte of INPUT.DAT from drive 0 into RAM beginning at $4000.
* This example assumes the file fits before the active stack at $7FFF.
************************************************************************
        ORG     $2000

Start:
        LDS     #$7FFF
        LDX     #ReadFilename
        JSR     DiskLibOpenRead
        BCS     ReadFailed
        LDX     #$4000
ReadLoop:
        JSR     DiskLibReadByte
        BCS     ReadStopped
        STA     ,X+
        BRA     ReadLoop
ReadStopped:
        CMPB    #DiskErrorEndOfFile
        BNE     ReadFailed
        JSR     DiskLibCloseRead
        BCS     ReadFailed
        JSR     DiskLibShutdown
ReadComplete:
        BRA     ReadComplete

ReadFailed:
        STB     LastDiskError
        JSR     DiskLibShutdown
ReadHalt:
        BRA     ReadHalt

ReadFilename:
        FCN     /INPUT.DAT:0/
LastDiskError:
        RMB     1

        INCLUDE ../../Generic_6809_Libraries/DECB_Disk_File_Library.asm
        END     Start

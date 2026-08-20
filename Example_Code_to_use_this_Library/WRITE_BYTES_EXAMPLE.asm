************************************************************************
* Create OUTPUT.DAT on drive 0 and append Payload one byte at a time.
************************************************************************
        ORG     $2000

Start:
        LDS     #$7FFF
        LDX     #WriteFilename
        CLRA                            * binary directory flag
        LDB     #1                      * DECB data-file type
        JSR     DiskLibOpenWrite
        BCS     WriteFailed
        LDX     #Payload
WriteLoop:
        LDB     ,X+
        JSR     DiskLibWriteByte
        CMPX    #PayloadEnd
        BLO     WriteLoop
        JSR     DiskLibCloseWrite
        BCS     WriteFailed
        JSR     DiskLibShutdown
WriteComplete:
        BRA     WriteComplete

WriteFailed:
        STB     LastDiskError
        JSR     DiskLibShutdown
WriteHalt:
        BRA     WriteHalt

WriteFilename:
        FCN     /OUTPUT.DAT:0/
Payload:
        FCC     /Written one byte at a time./
        FCB     13
PayloadEnd:
LastDiskError:
        RMB     1

        INCLUDE ../../Generic_6809_Libraries/DECB_Disk_File_Library.asm
        END     Start

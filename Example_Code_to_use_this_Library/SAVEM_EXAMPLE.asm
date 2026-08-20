************************************************************************
* Generic SAVEM example. This writes SAMPLE.BIN to floppy drive 1.
* DiskLibSaveM intentionally refuses to overwrite an existing file.
************************************************************************
        ORG     $2000

Start:
        LDS     #$7FFF
        LDX     #SaveFilename
        LDD     #PayloadStart           * first byte to save
        LDU     #PayloadEnd-1           * last byte, inclusive
        LDY     #PayloadStart           * EXEC address in file postamble
        JSR     DiskLibSaveM
        BCS     SaveFailed              * B = DiskError... value
        JSR     DiskLibShutdown
SaveComplete:
        BRA     SaveComplete            * save completed

SaveFailed:
        STB     LastDiskError
        JSR     DiskLibShutdown
SaveHalt:
        BRA     SaveHalt

SaveFilename:
        FCN     /SAMPLE.BIN:1/
LastDiskError:
        RMB     1

PayloadStart:
        LDA     #$3F
        STA     $FF22
PayloadHalt:
        BRA     PayloadHalt
PayloadEnd:

        INCLUDE ../../Generic_6809_Libraries/DECB_Disk_File_Library.asm
        END     Start

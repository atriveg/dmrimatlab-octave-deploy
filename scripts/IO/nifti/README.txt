This is a re-factorization of Jimmy Shen's functions to read/write NIfTI volumes available at the "Tools for NIfTI and ANALYZE image":

https://es.mathworks.com/matlabcentral/fileexchange/8797-tools-for-nifti-and-analyze-image

NOTE: we have kept just the essential functions allowing to read/write NIfTI volumes "as they are", removing re-slicing or graphical capabilities. Besides, this implementation will only work in Octave under Linux. On the other hand, we got rid of calls to gzip/gunzip and creating temporary raw (non-gzipped) data files to avoid additional massive I/O operations from/to the disk. This is a potential advantage if you store your data in external/network storage devices.

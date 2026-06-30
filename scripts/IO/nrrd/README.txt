This is a re-factorization of Andras Lasso's functions to read/write NRRD volumes available at the "Matlab Bridge extension for 3-D Slicer 4.5":

https://www.slicer.org/wiki/Documentation/4.5/Extensions/MatlabBridge

NOTE: we have kept just the essential functions allowing to read/write NRRD volumes "as they are". Besides, this implementation will only work in Octave under Linux. On the other hand, we got rid of Java-based gzip/gunzip pipelines, using instead Octave's piped I/O (popen, pclose; you need to have "gzip" and "tail" installed on your system, which are otherwise default programs in most distributions).

function nrrd = nrrdMakeHdr( volume, T, space, datatype )

if( nargin<1 )
    volume = single([]);
end

if( (nargin<2) || isempty(T) )
    T = eye(4);
end
if(size(T,1)<3)
    T = [ T; [0,0,0,1] ];
end

if( (nargin<3) || isempty(space) )
    space = 'right-anterior-superior';
end
if(length(space)==3)
    if(lower(space(1))=='r')
        tmp = 'right';
    else
        tmp = 'left';
    end
    if(lower(space(2))=='a')
        tmp = sprintf('%s-anterior',tmp);
    else
        tmp = sprintf('%s-posterior',tmp);
    end
    if(lower(space(3))=='i')
        tmp = sprintf('%s-inferior',tmp);
    else
        tmp = sprintf('%s-superior',tmp);
    end
    space = tmp;
end

if( (nargin<4) || isempty(datatype) )
    datatype = getMetaType(class(volume));
else
    volume   = cast(volume,datatype);
    datatype = getMetaType(datatype);
end

nrrd.metaData = createMetaData( size(volume), datatype, T, space );
nrrd.metaDataFieldNames = createMetaDataFieldNames;
nrrd.pixelData = volume;
nrrd.ijkToLpsTransform = T;

end

%---------------------------------------------------------------------
function fn = createMetaDataFieldNames
fn.space_directions = 'space directions';
fn.space_origin = 'space origin';
end

%---------------------------------------------------------------------
function md = createMetaData( sz, type, T, space )

if(length(sz)<3)
    sz(3) = 1;
end

md.type = type;
md.dimension = sprintf( '%d', length(sz) );
md.space = space;
md.sizes = sprintf('%d ',sz);

md.space_directions = sprintf('(%f,%f,%f) (%f,%f,%f) (%f,%f,%f)',reshape(T(1:3,1:3),1,9));
for d=4:length(sz)
    md.space_directions = sprintf('none %s',md.space_directions);
end

md.kinds = 'domain domain domain';
if(length(sz)==4)
    if( sz(1)==3 )
        md.kinds = sprintf('vector %s',md.kinds);
    elseif( sz(1)==6 )
        md.kinds = sprintf('3D-symmetric-matrix %s',md.kinds);
    else
        md.kinds = sprintf('list %s',md.kinds);
    end
elseif(length(sz)>4)
    for d=4:length(sz)
        md.kinds = sprintf('list %s',md.kinds);
    end
end

[~,~,endian] = computer();
if(endian=='L')
    md.endian = 'little';
else
    md.endian = 'big';
end

md.encoding = 'gzip';
md.space_origin = sprintf('(%f,%f,%f)',T(1,4),T(2,4),T(3,4));
end

%---------------------------------------------------------------------
function metaType = getMetaType(matlabType)
% Determine the metadata type from the Matlab type
switch (matlabType)
    case {'int8'}
        metaType = 'int8';
    case {'uint8'}
        metaType = 'uint8';
    case {'int16'}
        metaType = 'int16';
    case {'uint16'}
        metaType = 'uint16';
    case {'int32'}
        metaType = 'int32';
    case {'uint32'}
        metaType = 'uint32';
    case {'int64'}
        metaType = 'int64';
    case {'uint64'}
        metaType = 'uint64';
    case {'single'}
        metaType = 'float';
    case {'double'}
        metaType = 'double';
    otherwise
        assert(false, 'Unsupported Matlab data type')
end
end

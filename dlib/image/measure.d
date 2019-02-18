/*
Copyright (c) 2019- Ferhat Kurtulmuş
Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:
The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dlib.image.measure;

import std.stdio;
import std.algorithm.searching;
import std.math;
import std.typecons;
import std.array;
import core.stdc.float_;
import std.algorithm;

import dlib.image;
import dlib.image.fitellipse;
import dlib.math;
import dlib.container;

alias DfsFun = void function(int, int, ubyte, ubyte[], SuperImage);

uint row_count;
uint col_count;

immutable int[4] dx4 = [1, 0, -1,  0];
immutable int[4] dy4 = [0, 1,  0, -1];

immutable int[8] dx8 = [1, -1, 1, 0, -1,  1,  0, -1];
immutable int[8] dy8 = [0,  0, 1, 1,  1, -1, -1, -1];

// The reason for why 2 dfs functions are used is performace! I don't want
// the algorithm to check proximity rule (conn) at each pixel.

void dfs4(int x, int y, ubyte current_label, ubyte[] label, SuperImage img) {
    if (x < 0 || x == row_count) return;
    if (y < 0 || y == col_count) return;
    if (label[x*col_count + y] || !img.data[x*col_count + y]) return;
    
    label[x*col_count + y] = current_label;
    
    foreach(direction; 0..4)
        dfs4(x + dx4[direction], y + dy4[direction], current_label, label, img);
}

void dfs8(int x, int y, ubyte current_label, ubyte[] label, SuperImage img) {
    if (x < 0 || x == row_count) return;
    if (y < 0 || y == col_count) return;
    if (label[x*col_count + y] || !img.data[x*col_count + y]) return;
    
    label[x*col_count + y] = current_label;

    foreach(direction; 0..8)
        dfs8(x + dx8[direction], y + dy8[direction], current_label, label, img);
}

SuperImage bwlabel(SuperImage img, uint conn = 8){
    /* The algorithm is based on:
     * https://stackoverflow.com/questions/14465297/connected-component-labelling
     */
    /* testing:
    auto img = loadImage("test.png");
    
    auto imgbin = otsuBinarization(img);
    
    auto res = bwlabel(imgbin);
    // need an "imshow" function
    saveImage(res, "test_response_labeled.png");
    */
    
    row_count = img.height;
    col_count = img.width;
    
    auto label = uninitializedArray!(ubyte[])(row_count*col_count);
    auto res = new Image!(PixelFormat.L8)(col_count, row_count);
    
    DfsFun dfs;
    
    if(conn == 4)
        dfs = &dfs4;
    else
        dfs = &dfs8;
    
    ubyte component = 0;
    foreach (int i; 0..row_count) 
        foreach (int j; 0..col_count)
            if (!label[i*col_count + j] && img.data[i*col_count + j]) dfs(i, j, ++component, label, img);
    
    // the number of blobs is "label.maxElement"
    
    res.data[] = label[];
    return res;     
}

struct XYList {
    int[] xs;
    int[] ys;
}

struct Rectangle{
    int x;
    int y;
    int width;
    int height;
}

struct Ellipse{
    double angle;
    double center_x; 
    double center_y;
    double r1;
    double r2;
}

alias Point = Vector2i;

XYList bin2coords(SuperImage img){
    uint row_count = img.height;
    uint col_count = img.width;
    
    XYList coords;
    
    foreach (int i; 0..row_count) 
        foreach (int j; 0..col_count)
            if(img.data[i*col_count + j] == 255){
                    coords.xs ~= j;
                    coords.ys ~= i;
            }
    
    return coords;
}

private void _setValAtIdx_with_padding(SuperImage img, XYList xylist, int val, int pad = 2){
    uint row_count = img.height;
    uint col_count = img.width;
    
    foreach (i; 0..xylist.xs.length)
        img[xylist.xs[i]+pad/2, xylist.ys[i]+pad/2] = Color4f(val, val, val, 255);
}


XYList
getContinousBoundaryPoints( SuperImage unpadded){
    // https://www.codeproject.com/Articles/1105045/Tracing-Boundary-in-D-Image-Using-Moore-Neighborho
    int _rows = unpadded.height;
    int _cols = unpadded.width;
    int pad = 2;
    auto region = new Image!(PixelFormat.L8)(_cols + pad, _rows + pad); region.data[0..$] = 0;
    XYList coords = bin2coords(unpadded);
    _setValAtIdx_with_padding(region, coords, 1);
    
    DynamicArray!Vector2i BoundaryPoints;
    int Width_i = region.width;
    int Height_i = region.height;
    ubyte[] InputImage = region.data;
    if( InputImage !is null)
    {
        
        
        int nImageSize = Width_i * Height_i;
        
        int[][] Offset = [
                                [ -1, -1 ],       //  +----------+----------+----------+
                                [ 0, -1 ],        //  |          |          |          |
                                [ 1, -1 ],        //  |(x-1,y-1) | (x,y-1)  |(x+1,y-1) |
                                [ 1, 0 ],         //  +----------+----------+----------+
                                [ 1, 1 ],         //  |(x-1,y)   |  (x,y)   |(x+1,y)   |
                                [ 0, 1 ],         //  |          |          |          |
                                [ -1, 1 ],        //  +----------+----------+----------+
                                [ -1, 0 ]         //  |          | (x,y+1)  |(x+1,y+1) |
                            ];                    //  |(x-1,y+1) |          |          |
                                                  //  +----------+----------+----------+
        const int NEIGHBOR_COUNT = 8;
        auto BoundaryPixelCord = Vector2i(0, 0);
        auto BoundaryStartingPixelCord = Vector2i(0, 0);
        auto BacktrackedPixelCord = Vector2i(0, 0);
        int[][] BackTrackedPixelOffset = [ [0,0] ];
        bool bIsBoundaryFound = false;
        bool bIsStartingBoundaryPixelFound = false;
        for(int Idx = 0; Idx < nImageSize; ++Idx ) // getting the starting pixel of boundary
        {
            if( 0 != InputImage[Idx] )
            {
                BoundaryPixelCord.x = Idx % Width_i;
                BoundaryPixelCord.y = Idx / Width_i;
                BoundaryStartingPixelCord = BoundaryPixelCord;
                BacktrackedPixelCord.x = ( Idx - 1 ) % Width_i;
                BacktrackedPixelCord.y = ( Idx - 1 ) / Width_i;
                BackTrackedPixelOffset[0][0] = BacktrackedPixelCord.x - BoundaryPixelCord.x;
                BackTrackedPixelOffset[0][1] = BacktrackedPixelCord.y - BoundaryPixelCord.y;
                BoundaryPoints.append( BoundaryPixelCord );
                bIsStartingBoundaryPixelFound = true;
                break;
            }            
        }
        auto CurrentBoundaryCheckingPixelCord = Vector2i(0, 0);
        auto PrevBoundaryCheckingPixxelCord = Vector2i(0, 0);
        if( !bIsStartingBoundaryPixelFound )
        {
            BoundaryPoints.remove(1);
        }
        while( true && bIsStartingBoundaryPixelFound )
        {
            int CurrentBackTrackedPixelOffsetInd = -1;
            foreach( int Ind; 0..NEIGHBOR_COUNT )
            {
                if( BackTrackedPixelOffset[0][0] == Offset[Ind][0] &&
                    BackTrackedPixelOffset[0][1] == Offset[Ind][1] )
                {
                    CurrentBackTrackedPixelOffsetInd = Ind;// Finding the bracktracked 
                                                           // pixel's offset index
                    break;
                }
            }
            int Loop = 0;
            while( Loop < ( NEIGHBOR_COUNT - 1 ) && CurrentBackTrackedPixelOffsetInd != -1 )
            {
                int OffsetIndex = ( CurrentBackTrackedPixelOffsetInd + 1 ) % NEIGHBOR_COUNT;
                CurrentBoundaryCheckingPixelCord.x = BoundaryPixelCord.x + Offset[OffsetIndex][0];
                CurrentBoundaryCheckingPixelCord.y = BoundaryPixelCord.y + Offset[OffsetIndex][1];
                int ImageIndex = CurrentBoundaryCheckingPixelCord.y * Width_i + 
                                    CurrentBoundaryCheckingPixelCord.x;
                
                if( 0 != InputImage[ImageIndex] )// finding the next boundary pixel
                {
                    BoundaryPixelCord = CurrentBoundaryCheckingPixelCord; 
                    BacktrackedPixelCord = PrevBoundaryCheckingPixxelCord;
                    BackTrackedPixelOffset[0][0] = BacktrackedPixelCord.x - BoundaryPixelCord.x;
                    BackTrackedPixelOffset[0][1] = BacktrackedPixelCord.y - BoundaryPixelCord.y;
                    BoundaryPoints.append( BoundaryPixelCord );
                    break;
                }
                PrevBoundaryCheckingPixxelCord = CurrentBoundaryCheckingPixelCord;
                CurrentBackTrackedPixelOffsetInd += 1;
                Loop++;
            }
            if( BoundaryPixelCord.x == BoundaryStartingPixelCord.x &&
                BoundaryPixelCord.y == BoundaryStartingPixelCord.y ) // if the current pixel = 
                                                                     // starting pixel
            {
                BoundaryPoints.remove(1);
                bIsBoundaryFound = true;
                break;
            }
        }
        if( !bIsBoundaryFound ) // If there is no connected boundary clear the list
        {
            BoundaryPoints.remove(cast(int)BoundaryPoints.length);
        }
    }
    XYList xys;
    foreach(i; 0..BoundaryPoints.length){
        xys.xs ~= BoundaryPoints[i].x - pad/2;
        xys.ys ~= BoundaryPoints[i].y - pad/2;
    }
    return xys;
}

double contourArea(XYList xylist){
    auto npoints = xylist.xs.length;

    if( npoints == 0 ) return 0.0;
    
    double a00 = 0;
    auto prev = Vector2f(xylist.xs[npoints-1], xylist.ys[npoints-1]);

    for( int i = 0; i < npoints; i++ )
    {
        auto p = Vector2f(cast(float)xylist.xs[i], cast(float)xylist.ys[i]);
        a00 += cast(double)prev.x * p.y - cast(double)prev.y * p.x;
        prev = p;
    }

    a00 *= 0.5;

    return abs(a00);
}
double arcLength(XYList xylist){
    double perimeter = 0;
    int count = cast(int)xylist.xs.length;
    int i;

    if( count <= 1 )
        return 0;
    
    int last = count-1;

    auto prev = Vector2f(xylist.xs[last], xylist.ys[last]);

    for( i = 0; i < count; i++ )
    {
        auto p = Vector2f(cast(float)xylist.xs[i], cast(float)xylist.ys[i]);
        float d_x = p.x - prev.x, d_y = p.y - prev.y;
        perimeter += sqrt(d_x*d_x + d_y*d_y);

        prev = p;
    }

    return perimeter;
}

Rectangle boundingBox(XYList xylist){
    int minx = xylist.xs.minElement;
    int miny = xylist.ys.minElement;
    int width = xylist.xs.maxElement - xylist.xs.minElement;
    int height = xylist.ys.maxElement - xylist.ys.minElement;
    
    Rectangle rect = {x: minx, y: miny, width: width, height: height};
    return rect;
}

Tuple!(Rectangle[], XYList[])
bboxesAndIdxFromLabelImage(SuperImage labelIm){
    int row_count = labelIm.height;
    int col_count = labelIm.width;
    
    immutable int ncomps = labelIm.data.maxElement;
    
    XYList[] segmentedImgIdx;
    segmentedImgIdx.length = ncomps;
    
    foreach (int i; 0..row_count) 
        foreach (int j; 0..col_count)
            foreach(label; 0..ncomps){
                if(labelIm.data[i*col_count + j] == label+1){
                    segmentedImgIdx[label].xs ~= j;
                    segmentedImgIdx[label].ys ~= i;
                }
            }
    Rectangle[] recs; recs.length = ncomps;
    foreach(i; 0..ncomps){
        recs[i] = boundingBox(segmentedImgIdx[i]);
    }
    return tuple(recs, segmentedImgIdx);
}

SuperImage idxListToSubImage(Rectangle rect, XYList idxlist){
    
    auto res = new Image!(PixelFormat.L8)(rect.width, rect.height);
    
    int yOffset = rect.y;
    int xOffset = rect.x;
    
    foreach(i; 0..idxlist.xs.length){
        res[idxlist.xs[i]-xOffset, idxlist.ys[i]-yOffset] = Color4f(255, 255, 255, 255);
    }
    
    return res;
    
}

SuperImage subImage(SuperImage img, Rectangle ROI){
    //this copies vals for new image :(
    int col_count = img.width;
    auto subIm = new Image!(PixelFormat.L8)(ROI.width, ROI.height);
    ubyte* ptr = subIm.data.ptr;
    
    foreach (int i; ROI.y..ROI.y+ROI.height) 
        foreach (int j; ROI.x..ROI.x+ROI.width){
            *ptr = img.data[i*col_count + j];
            ptr ++;
        }
    
    return subIm;
}

private void setValAtIdx(SuperImage img, XYList xylist, int val){
    uint row_count = img.height;
    uint col_count = img.width;
    //int pad = 2;
    foreach (i; 0..xylist.xs.length)
        img[xylist.xs[i], xylist.ys[i]] = Color4f(val, val, val, 255);
}


Tuple!(ulong[], ulong[]) grid(int rows, int cols){
    ulong[] xGrid; xGrid.length = cols * rows;
    xGrid[0..$] = 0;
    foreach(i; 0..rows)
        foreach(j; 0..cols){
            xGrid[i*cols + j] = i;
        }
    
    ulong[] yGrid; yGrid.length = cols * rows;
    yGrid[0..$] = 0;
    foreach(i; 0..rows)
        foreach(j; 0..cols){
            yGrid[i*cols + j] = j;
        }
    return tuple(xGrid, yGrid);
}


private void calculateMoments(Region region){
    // experimental based on: https://github.com/shackenberg/Image-Moments-in-Python
    
    auto imbin = region.image;
    
    XYList xylist = region.pixelList;
    auto mgrid = grid(imbin.height, imbin.width);
    auto xGrid = mgrid[0];
    auto yGrid = mgrid[1];
    
    double m00 = 0, m10 = 0, m01 = 0, m20 = 0, m11 = 0, m02 = 0, m30 = 0, m21 = 0, m12 = 0, m03 = 0;
    double mu20 = 0, mu11 = 0, mu02 = 0, mu30 = 0, mu21 = 0, mu12 = 0, mu03 = 0;
    double mean_x = 0, mean_y = 0;
    double nu20 = 0, nu11 = 0, nu02 = 0, nu30 = 0, nu21 = 0, nu12 = 0, nu03 = 0;
    
    // raw or spatial moments
    m00 = xylist.xs.length;
    
    foreach(i; 0..imbin.height * imbin.width){
        m01 += xGrid[i]*(imbin.data[i]/255);
        m10 += yGrid[i]*(imbin.data[i]/255);
        m11 += yGrid[i]*xGrid[i]*(imbin.data[i]/255);
        m02 += (xGrid[i]^^2)*(imbin.data[i]/255);
        m20 += (yGrid[i]^^2)*(imbin.data[i]/255);
        m12 += xGrid[i]*(yGrid[i]^^2)*(imbin.data[i]/255);
        m21 += (xGrid[i]^^2)*yGrid[i]*(imbin.data[i]/255);
        m03 += (xGrid[i]^^3)*(imbin.data[i]/255);
        m30 += (yGrid[i]^^3)*(imbin.data[i]/255);
    }
    
    // central moments
    mean_x = m01/m00;
    mean_y = m10/m00;
    
    foreach(i; 0..imbin.height * imbin.width){ // for now, an extra loop is required here
        mu11 += (xGrid[i] - mean_x) * (yGrid[i] - mean_y)*(imbin.data[i]/255);
        mu02 += ((yGrid[i] - mean_y)^^2)*(imbin.data[i]/255);
        mu20 += ((xGrid[i] - mean_x)^^2)*(imbin.data[i]/255);
        mu12 += (xGrid[i] - mean_x) * ((yGrid[i] - mean_y)^^2)*(imbin.data[i]/255);
        mu21 += ((xGrid[i] - mean_x)^^2) * (yGrid[i] - mean_y)*(imbin.data[i]/255);
        mu03 += ((yGrid[i] - mean_y)^^3)*(imbin.data[i]/255);
        mu30 += ((xGrid[i] - mean_x)^^3)*(imbin.data[i]/255);
    }
    
    // central standardized or normalized or scale invariant moments
    nu11 = mu11 / m00^^(2);
    nu12 = mu12 / m00^^(2.5);
    nu21 = mu21 / m00^^(2.5);
    nu20 = mu20 / m00^^(2);
    nu03 = mu03 / m00^^(2.5); // skewness
    nu30 = mu30 / m00^^(2.5); // skewness
    
    region.m00 = m00; region.m10 = m10; region.m01 = m01; region.m20 = m20;
    region.m11 = m11; region.m02 = m02; region.m30 = m30; region.m21 = m21;
    region.m12 = m12; region.m03 = m03; 
    
    region.mu20 = mu20; region.mu11 = mu11; region.mu02 = mu02;
    region.mu30 = mu30; region.mu21 = mu21; region.mu12 = mu12; region.mu03 = mu03;
    region.nu20 = nu20; region.nu11 = nu11; region.nu02 = nu02;
    region.nu30 = nu30; region.nu21 = nu21; region.nu12 = nu12; region.nu03 = nu03;
}

class Region{
    SuperImage image;
    
    // moments
    double m00, m10, m01, m20, m11, m02, m30, m21, m12, m03,
    mu20, mu11, mu02, mu30, mu21, mu12, mu03,
    nu20, nu11, nu02, nu30, nu21, nu12, nu03;
    
    ulong area;
    double areaFromContour;
    double perimeter;
    Point centroid;
    double aspect_Ratio;
    Rectangle bBox;
    //XYList convexHull;
    //double convexArea;
    Ellipse ellipse;
    double extent;
    //double solidity;
    double majorAxisLength;
    double minorAxisLength;
    //double orientation;
    double eccentricity;
    double equivalentDiameter;
    XYList contourPixelList; // chain sorted!
    XYList pixelList;
    
    this(){}
}

class RegionProps{
    // Experimental. It computes spatial moments, centroid, perimeter, ellipse and area correctly
    /*
    auto img = loadImage("test.png");
    auto imgbin = otsuBinarization(img);
    
    auto rp = new RegionProps(imgbin);
    rp.calculateProps();
    
    foreach(i, region; rp.regions){
        imgbin[region.centroid.x, region.centroid.y] = Color4f(0, 0, 0, 255);
        
    }
    
    */
    Region[] regions;
    SuperImage parentBin;
    SuperImage labelIm;
    
    int parentHeight;
    int parentWidth;
    
    Rectangle[] bboxes;
    XYList[] coords;
    
    int count = 0;
    
    this(SuperImage imbin){
        parentHeight = imbin.height;
        parentWidth = imbin.width;
        
        parentBin = imbin;
        
        labelIm = bwlabel(parentBin);
        
        auto _tupBboxesAndIdx = bboxesAndIdxFromLabelImage(labelIm);
        bboxes = _tupBboxesAndIdx[0];
        coords = _tupBboxesAndIdx[1];
        
        count = cast(int)bboxes.length;
        
        regions.length = count;
    }
    
    void calculateProps(){
        foreach(i; 0..count){
            Region region = new Region();
            region.bBox = bboxes[i];
            SuperImage imsub = idxListToSubImage(bboxes[i],coords[i]);
            auto contourIdx_sorted = getContinousBoundaryPoints(imsub);
            
            region.image = imsub;
            
            region.aspect_Ratio = region.bBox.width / cast(double)region.bBox.height;
            region.extent = cast(double)region.area/(region.bBox.width*region.bBox.height);
            
            region.perimeter = arcLength(contourIdx_sorted); // holes are ignored
            region.areaFromContour = contourArea(contourIdx_sorted); // holes are ignored
            region.area = coords[i].xs.length;
            region.pixelList = coords[i];
            region.contourPixelList = contourIdx_sorted;
            
            calculateMoments(region);
            
            // centroid is computed correctly, so we ensure that raw moments are correct
            region.centroid = Point(cast(int)round(region.m10/region.m00) + region.bBox.x,
                                    cast(int)round(region.m01/region.m00) + region.bBox.y);
            // or region.centroid = Point(cast(int)round(mean(coords[i].xs)), cast(int)round(mean(coords[i].ys)));
            
            region.equivalentDiameter = sqrt(4*region.area/PI);
            
            Ellipse _ellipse = ellipseFit(contourIdx_sorted);
            _ellipse.center_x += region.bBox.x;
            _ellipse.center_y += region.bBox.y;
            
            region.ellipse = _ellipse;
            
            if(region.ellipse.r1 > region.ellipse.r2){
                region.majorAxisLength = 2*region.ellipse.r1;
                region.minorAxisLength = 2*region.ellipse.r2; 
            }else{
                region.majorAxisLength = 2*region.ellipse.r2;
                region.minorAxisLength = 2*region.ellipse.r1;
            }
            
            region.eccentricity = sqrt(1.0 - (region.minorAxisLength / region.majorAxisLength) * (region.minorAxisLength / region.majorAxisLength));
            
            regions[i] = region;
            
        }
    }
}

// TODO: implement convex hull to calculate more props

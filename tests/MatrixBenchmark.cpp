// Simulation only: excludes presentation, desktop composition and driver costs.
#include "../src/MatrixDesktop.cpp"
#include <chrono>
#include <iostream>
int main() {
 started=GetTickCount64();
 if(!EnsureSurface(2880,1800,28))return 1;
 for(int i=0;i<200;i++)Advance(50);
 auto begin=std::chrono::steady_clock::now();
 for(int i=0;i<1000;i++)Advance(50);
 auto end=std::chrono::steady_clock::now();
 double ms=std::chrono::duration<double,std::milli>(end-begin).count()/1000;
 std::cout<<"2880x1800 simulation: "<<ms<<" ms/frame, "<<activePixels.size()<<" active pixels; excludes compositor and uploads.\n";
 FreeSurface();
}

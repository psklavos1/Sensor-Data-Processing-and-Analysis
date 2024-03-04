from cmath import sqrt

#calculating the distance between two points    
def distance(x1,x2,y1,y2):
 return (sqrt( (abs(x2 - x1)**2) + (abs(y2 - y1)**2 ))).real



#create Sensors and find the neighbours of each Sensor

def topology_generator(D , R):

    grid = [[1 for x in range(D)] for y in range(D)]

    for j in range(0,D*D):
        grid[int(j/D)][j%D]=j
    print(grid)
   
#open Mytopology.txt and write them to the file 
    f = open("myTopology.txt","w+")

    for k in range(0,D*D):
      for m in range(0,D*D):
       if distance(int(m/D),int(k/D),m%D,k%D) <= R:
 
        f.write("%s %s -50.0\n" % (grid[int(k/D)][k%D],grid[int(m/D)][m%D]) )   
        print(grid[int(k/D)][k%D],grid[int(m/D)][m%D])
       

#main

if __name__ == '__main__':
    # Get input for grid size and sensor range
 
     D = int(input("Enter grid size (max 8): "))
     R = float(input("Enter sensor range: "))

topology_generator(D,R)

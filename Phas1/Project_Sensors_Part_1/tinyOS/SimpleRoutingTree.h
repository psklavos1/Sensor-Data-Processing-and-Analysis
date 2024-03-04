#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H


enum{
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	AM_SIMPLEROUTINGTREEMSG=22,
	AM_ROUTINGMSG=22,
        AM_MYMSG=12,
	SEND_CHECK_MILLIS=70000,
	TIMER_PERIOD_MILLI=30*1024,
	TIMER_FAST_PERIOD=256
,

        
        BOOT_TIME = 1024*10,               //Xronos poy tha parei to booting twn censors       
        ROUTING_TIME = 1024*2,     	   //Xronos poy tha parei to routing 
        NUM_MAX_QUERIES = 2,
        NUM_MAX_CHILDREN =20,

        COUNT=1,
        MAX = 2,
	BOTH = 3,
        
};
/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/
typedef nx_struct RoutingMsg
{
	// nx_uint16_t senderID;
	nx_uint8_t depth;
        nx_uint8_t tct;
        nx_uint8_t operation;
} RoutingMsg;

//typedef nx_struct MyMsg
//{
//
//
//	
//        nx_uint8_t depth;
//} MyMsg;


typedef nx_struct Measurement
{
	nx_uint8_t measurement;
	
} Measurement;



typedef nx_struct TwoMeasurements
{
	nx_uint8_t count;
	nx_uint8_t max;
} TwoMeasurements;


typedef struct Children{

        nx_uint16_t childrenId;
        nx_uint16_t max;
        nx_uint8_t count;
        
        
}Children;
  
#endif

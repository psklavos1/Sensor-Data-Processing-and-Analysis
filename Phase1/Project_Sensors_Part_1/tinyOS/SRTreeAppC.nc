#include "SimpleRoutingTree.h"


configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;

#if defined(DELUGE) //defined(DELUGE_BASESTATION) || defined(DELUGE_LIGHT_BASESTATION)
	components DelugeC;
#endif

#ifdef PRINTFDBG_MODE
		components PrintfC;
#endif
	components MainC, ActiveMessageC,RandomC,RandomMlcgC;

	components new TimerMilliC() as RoutingMsgTimerC;
        components new TimerMilliC() as MyTimerC;
        components new TimerMilliC() as RoundTimerC;

	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;

	components new AMSenderC(AM_MYMSG) as MySenderC;
	components new AMReceiverC(AM_MYMSG) as MyReceiverC;


	components new PacketQueueC(SENDER_QUEUE_SIZE) as MySendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as MyReceiveQueueC;

	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;

	
	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.RadioControl -> ActiveMessageC;
        
        //RANDOM
        SRTreeC.Random->RandomC;
        SRTreeC.Seed->RandomMlcgC.SeedInit;
	
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
        SRTreeC.MyTimer->MyTimerC;
        SRTreeC.RoundTimer->RoundTimerC;	

	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;
	

	SRTreeC.MyPacket->MySenderC.Packet;
	SRTreeC.MyAMPacket->MySenderC.AMPacket;
	SRTreeC.MyAMSend->MySenderC.AMSend;
	SRTreeC.MyReceive->MyReceiverC.Receive;


	
	SRTreeC.MySendQueue->MySendQueueC;
	SRTreeC.MyReceiveQueue->MyReceiveQueueC;
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;

	
}

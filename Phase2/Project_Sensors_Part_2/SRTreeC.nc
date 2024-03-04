#include "SimpleRoutingTree.h"
#ifdef PRINTFDBG_MODE
	#include "printf.h"
#endif

module SRTreeC
{
        uses interface Random;
        uses interface ParameterInit<uint16_t> as Seed; 
       
	uses interface Boot;
	uses interface SplitControl as RadioControl;

	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	
	uses interface AMSend as MyAMSend;
	uses interface AMPacket as MyAMPacket;
	uses interface Packet as MyPacket;

        uses interface AMSend as OpAMSend;
	uses interface AMPacket as OpAMPacket;
	uses interface Packet as OpPacket;

	uses interface Timer<TMilli> as RoundTimer;
	uses interface Timer<TMilli> as RoutingMsgTimer;
        uses interface Timer<TMilli> as MyTimer;
	uses interface Timer<TMilli> as UpdateOpTimer;

	
	uses interface Receive as RoutingReceive;
	uses interface Receive as MyReceive;
	uses interface Receive as OpReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as MySendQueue;
	uses interface PacketQueue as MyReceiveQueue;

        uses interface PacketQueue as OpSendQueue;
	uses interface PacketQueue as OpReceiveQueue;
}
implementation
{
        uint16_t  roundCounter;
        
        // MESSAGES
        message_t radioRoutingSendPkt;
	message_t radioMySendPkt;
        message_t radioOpSendPkt;

        //MEASUREMENT VALUE OF NODE
        uint8_t value;
	uint8_t same_level_variator;
	//FLAG FOR FINISHED ROUTING
        bool isFinished = FALSE;

	bool RoutingSendBusy=FALSE;
	bool MySendBusy=FALSE;
        bool OpSendBusy = FALSE;
        bool op_changed = FALSE;
        
        uint16_t prevCount;
        uint16_t prevMax;

	uint8_t curdepth;
	uint16_t parentID;

        uint8_t operation;
     
        //tct
        uint8_t tct;
        float random_step_size=0.1;

	//Array of structs children storing its values
        Children array_children[NUM_MAX_CHILDREN];
      
	task void sendRoutingTask();
	task void sendMyTask();
	task void sendOpTask();

	task void receiveRoutingTask();
	task void receiveMyTask();
	task void receiveOpTask();

        
        /* Helper Functions */ 

        uint32_t max_calculation(uint8_t my_measurement){
                uint32_t max;
                uint8_t i;
                max = my_measurement;  
                dbg("SRTreeC","Node's Measurement %d\n", max);
                for(i=0; i<NUM_MAX_CHILDREN && array_children[i].childrenId !=0 ;i++)
                {  
                        dbg("SRTreeC","ChildrenId: %d \t Of: %d \t MAX: %d\n", array_children[i].childrenId, TOS_NODE_ID, array_children[i].max);
                        // Max between my measurement and my children
                        max = (max > array_children[i].max) ? max : array_children[i].max;
                }
                dbg("SRTreeC","Node's MAX %d\n", max);
                return max;
        }

        uint32_t count_calculation(){
                uint32_t count; 
                uint8_t i;
                count =1;  
                // dbg("SRTreeC","Node's Self Count %d\n", count);

                for(i=0; i<NUM_MAX_CHILDREN && array_children[i].childrenId !=0 ;i++)
                {
                        dbg("SRTreeC","ChildrenId: %d \t Of: %d \t COUNT: %d  \n", array_children[i].childrenId, TOS_NODE_ID, array_children[i].count);
                        count += array_children[i].count;
                }
                // if (array_children[i].childrenId ==0){
                //         dbg("SRTreeC","i that stopped %d  \n", i);   
                // }

                dbg("SRTreeC","Node's COUNT %d\n", count);   
                return count;
        }

        void children_init(){
                uint8_t i;
                for(i=0 ; i< NUM_MAX_CHILDREN; i++){
                        array_children[i].childrenId=0;
                        array_children[i].max=0;
                        array_children[i].count=0;
                }
        }

	/* =================== Events =================== */
        /* Boot Event */ 
	event void Boot.booted(){
                uint16_t  seedNumber;
                FILE *file;
                call RadioControl.start();
                // init operation
                operation = 0;

                //gia na allazoume times sto RANDOM
                file = fopen("/dev/urandom","r");
                fread(&seedNumber,sizeof(seedNumber),1,file);
                fclose(file);
                call Seed.init(seedNumber + TOS_NODE_ID +1);
                roundCounter =0;

		if(TOS_NODE_ID==0)
		{
			curdepth=0;
			parentID=0;
			// dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			// dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
	}

	/* Radio Init Done Event */  
	event void RadioControl.startDone(error_t err)
	{   
                if (err == SUCCESS){
                        // dbg("Radio" , "Radio initialized successfully!!!\n");
                        children_init();
                        
                        // Timer to start taking measurements after routing is finished
                        call MyTimer.startOneShot(ROUTING_TIME);
                        // Timer to change epochs every 30s. 
                        call RoundTimer.startPeriodicAt(-(BOOT_TIME),TIMER_PERIOD_MILLI);

                        if (TOS_NODE_ID==0)
                        {
                                // Timer for sending routing message
                                call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
                        }
                }
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");
			call RadioControl.start();
		}
	}
	
        /* Radio Stopped Event*/ 
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n"); 
	}

        /* AMSend and Receive Pairs */ 
        /* Send Routing Msg Event*/ 
        event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		// dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}
	}
	
        /* Receive Routing Msg Event*/ 
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		// dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		// dbg("SRTreeC", "Routing: Something received!!!  from %u\n",msource);
		//dbg("SRTreeC", "Something received!!!\n");
		
		atomic{
		        memcpy(&tmp,msg,sizeof(message_t));
		        //tmp=*(message_t*)msg;
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");
		}
		
		// dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}

        /* Send Measurement Msg Event  */ 
        event void MyAMSend.sendDone(message_t* msg, error_t err)
	{		
		// dbg("SRTreeC" , "value Package sent %s \n", (err==SUCCESS)?"True":"False");
		if(!(call MySendQueue.empty()))
		{
			post sendMyTask();
		}	
	}

        /* Receive Measurement Msg Event*/ 
        event message_t *MyReceive.receive(message_t* msg, void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;

		msource = call MyAMPacket.source(msg);
		
		// dbg("SRTreeC", "### MyReceive.receive() start ##### \n");
		dbg("SRTreeC", "MyReceive: A value received!!!  from %u  \n", msource);

		atomic{
		        memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call MyReceiveQueue.enqueue(tmp);
		
		if( enqueueDone== SUCCESS)
		{
			post receiveMyTask();
		}
		else
		{
			dbg("SRTreeC","MyMsg enqueue failed!!! \n");
		}
		// dbg("SRTreeC", "### MyReceive.receive() end ##### \n");
		return msg;
	}

        /* Send Operation Msg Event*/ 
        event void OpAMSend.sendDone(message_t * msg , error_t err)
	{
		if(!(call OpSendQueue.empty()))
		{
		        dbg("SRTreeC", "Inside Send Done Op: %s \n",(err==SUCCESS)?"True":"False"); 
			post sendOpTask();
		}
	}
	
        /* Receive Operation Msg Event*/ 
	event message_t* OpReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call OpAMPacket.source(msg);
		// dbg("SRTreeC", "Operation Update: Something received!!!  from %u\n",msource);
                // dbg("SRTreeC", "Operation Changed: %s\n",(op_changed) ? "TRUE" : "FALSE");
		
		atomic{
		        memcpy(&tmp,msg,sizeof(message_t));
		        //tmp=*(message_t*)msg;
		}
		enqueueDone=call OpReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveOpTask();
		}
		else
		{
			dbg("SRTreeC","OpMsg enqueue failed!!! \n");
		}
		
		// dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}

        /* /AMSend and Receive Pairs */ 

        /* Timers Fired */
        event void RoutingMsgTimer.fired()
	{
	        message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		// dbg("SRTreeC", "RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
                roundCounter+=1;

                if (TOS_NODE_ID==0){	
                        // Random selection with 3 outcomes:
                        // operation = MAX;
                        // 1: Count, 2: Max, 3: Both
                        operation = ((call Random.rand16())%3)+1;
                        dbg("SRTreeC","Operation selected is: %d\n",operation); 
                        dbg("SRTreeC","Operation = 1 -> COUNT \t Operation = 2 -> MAX \t Operation = 3 -> BOTH\n"); 
                        
                        
                        //RANDOM TCT 5 ,10, 15,20
                        tct = (((call Random.rand16())%4)+1)*5;
                        dbg("SRTreeC", "Tct selected is : %d \n",tct);

                        dbg("SRTreeC", "\n\n\n========================================== ROUND %u ==========================================\n", roundCounter);
                        
                        //call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
                        //AFERESI TIS PARAPANW GRAMMIS DIOTI DEN KALEITE O MEsTRITIS PERIODIKA ALLA MONO STIS PRWTI EPOXI 1
                }
                if(call RoutingSendQueue.full())
                {
                        dbg("SRTreeC","RoutingSendQueue is full \n");
                        return;
                }
                        
                mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
                if(mrpkt==NULL)
                {
                        dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
                        return;
                }

                atomic{
                        mrpkt->depth = curdepth;
                        mrpkt->operation = operation;
                        mrpkt->tct=tct;
                }

                // dbg("SRTreeC" , "Sending RoutingMsg... \n");
                //isws DEN XREIAZOMASTE TA DYO KATW GIATI TA PERNAME STO AMSEND ROUTING TASK
                call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
                call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
                
                enqueueDone=call RoutingSendQueue.enqueue(tmp);
                
                if(enqueueDone==SUCCESS)
                {
                        if (call RoutingSendQueue.size()==1)
                        {
                                // dbg("SRTreeC", "SendRoutingTask() posted!!\n");
                                post sendRoutingTask();
                        }
                        
                        // dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
                }
                else
                {
                        dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
                }		
        }

        /* Measurement Msg */ 
        event void MyTimer.fired()
        {
                message_t tmp;
                Measurement *mypckt;
                error_t enqueueDone;
                uint8_t upper, lower=0;
                // dbg("SRTreeC", "Operation %d\n",operation);

                //stin if mpainei mono otan den exei ginei routing diladi stin proti epoxi gia na pei pote na xtupaei o metritis tou kathe komvou kai meta den ksanabenei afou theTw tin Routing TRUE
                if(!isFinished)
                {
                        // dbg("SRTreeC", "=================================================TOS_NODE_ID: %d\t %d\n", TOS_NODE_ID,curdepth);
                        same_level_variator = (call Random.rand16())%(TIMER_FAST_PERIOD);
                        isFinished = TRUE; 
                        dbg("SRTreeC", "Routing was finished!!! \t My depth: %d \t My parent: %d\n",curdepth, parentID);
                        call MyTimer.startPeriodicAt((-(BOOT_TIME)-((curdepth+1)*TIMER_FAST_PERIOD)+(same_level_variator)),TIMER_PERIOD_MILLI);
                        return;
                }
 
                // dbg("SRTreeC", "Measurements node %d, curdepth %d  \n",TOS_NODE_ID,curdepth); 

                // if (TOS_NODE_ID !=0)
                // { 
                //         dbg("SRTreeC", " The measurements will be sent to the parent \n"); 
                // }
                

                // The measurement of the node in notdifferent by more than 10%
                // to the last one(given this is not the first)
                if(value !=0){
                        upper = (1+random_step_size)*value;
                        lower = (1-random_step_size)*value;
                        value = ((call Random.rand16())%(upper - lower + 1)) + lower;
                        if(value == 0)
                                value = 1;
                }
                else { // The first measurement is random in range [1,80]
                        value = ((call Random.rand16())%80)+1;
                }
                
                // dbg("SRTreeC", "The value of node %d is %d in depth: %d\n",TOS_NODE_ID,value,curdepth);
                                                        
                if(call MySendQueue.full())
                {
                        dbg("SRTreeC", "Mysendqueue is full! \n");
                        return;
                }

                // Enque the message containing the value of the Node
                call MyAMPacket.setDestination(&tmp,parentID);

                mypckt = (Measurement*)(call MyPacket.getPayload(&tmp, sizeof(Measurement)));
                call MyPacket.setPayloadLength(&tmp,sizeof(Measurement));

                if(mypckt == NULL)
                {
                        dbg("SRTreeC", "  MY TIMER FIRED : No valid payload \n");
                }
                mypckt->measurement = value;
                
                //ENQUEUE
                enqueueDone = call MySendQueue.enqueue(tmp);

                if(enqueueDone ==SUCCESS)
                {
                        if(call MySendQueue.size() == 1)
                        {

                                post sendMyTask();
                        }
                }

                else {
                        dbg("SRTreeC", " My message failed to be enqueued !!! \n") ; 
                }  
        }
        
        /* Change of epoch */
        event void RoundTimer.fired()
        {        
                uint8_t new_op;
                uint8_t num;
                op_changed = FALSE;

                // Just to print the round at the start of an epoch to separate them
                roundCounter++;
                if(roundCounter>30)
                        return;

                if (TOS_NODE_ID == 0)
                {
                        dbg("SRTreeC", "\n\n\n========================================== ROUND %u ==========================================\n", roundCounter);
                        
                        // For Tos == 0: 1. Generate random 2. Assign new op 3. Send
                        num = (call Random.rand16())%10;
                        dbg("SRTreeC", "Random Number Chosen: %d\n", num);
                        op_changed = (num==0) ? TRUE : FALSE;
                        if(op_changed)
                        {
                                dbg("SRTreeC","\n====================================== Operation Update =====================================\n"); 
                                // Το secure that a different number is chosen. 1/3 probability to repeat.
                                do{
                                        new_op = ((call Random.rand16())%3)+1;
                                }while(new_op == operation);
                                operation = new_op;
                                // operation = COUNT;
                                dbg("SRTreeC","Updated Operation To be executed: %d\n", operation); 
                                dbg("SRTreeC","Operation = 1 -> COUNT \t Operation = 2 -> MAX \t Operation = 3 -> BOTH\n");
                                call UpdateOpTimer.startOneShot(0);  // Immediately start updating the op in the tree. 
                        } else{
                                dbg("SRTreeC","Operation did not change. Remains %d\n", operation);
                                dbg("SRTreeC","Operation = 1 -> COUNT \t Operation = 2 -> MAX \t Operation = 3 -> BOTH\n"); 
                        }
                }
        }

        event void UpdateOpTimer.fired()
        {
                message_t tmp;
		error_t enqueueDone;
		OpMsg* mrpkt;
                // ToDo Send opMsg
                if(call OpSendQueue.full())
                {
                        dbg("SRTreeC","OpSendQueue is full \n");
                        return;
                }
                        
                mrpkt = (OpMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(OpMsg)));
                if(mrpkt==NULL)
                {
                        dbg("SRTreeC","RoundTimer.fired(): No valid payload... \n");
                        return;
                }

                atomic{
                        mrpkt->operation = operation;
                }

                // dbg("SRTreeC" , "Sending OpgMsg... \n");
                call OpAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
                call OpPacket.setPayloadLength(&tmp, sizeof(OpMsg));
                enqueueDone=call OpSendQueue.enqueue(tmp);
                
                if(enqueueDone==SUCCESS)
                {
                        if (call OpSendQueue.size()==1)
                        {
                                // dbg("SRTreeC", "SendOpTask() posted!!\n");
                                post sendOpTask();
                        }          
                        // dbg("SRTreeC","OpMsg enqueued successfully in SendingQueue!!!\n");
                }
                else
                {
                        dbg("SRTreeC","OpMsg failed to be enqueued in SendingQueue!!!");
                }		
        }
        /* /Timers Fired*/ 
        /*=================== \Events ===================*/ 

	/*======================= Tasks =======================*/ 
        
        // Routing Send-Receive Pair 
        /* Send Routing Msg Task */ 
	task void sendRoutingTask()
	{
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
	        if (call RoutingSendQueue.empty())
		{
			dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
			return;
		}
		
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			return;
		}

                //dequeue to minima apo tin oura
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);

		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("SRTreeC","sendRoutingTask(): Unknown message!!!\n");
			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
		}
		else
		{
			dbg("SRTreeC","sendRoutingTask(): send failed!!!\n");
		}
	}
	
        /* Receive Routing Msg Task */ 
	task void receiveRoutingTask()
	{
		// message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
                uint16_t source;

		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		// dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);
		source = call RoutingAMPacket.source(&radioRoutingRecPkt);
		
		if(len == sizeof(RoutingMsg))
		{
			if ( (parentID<0)||(parentID>=65535))
			{
				// tote den exei akoma patera
				//parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
				//curdepth= mpkt->depth + 1;
                                RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
                                parentID = source;
                                curdepth = mpkt->depth+1;
                                operation = mpkt->operation;
                                tct = mpkt->tct;
				// printf("NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);

                                if (TOS_NODE_ID!=0)
                                {
                                        call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);  //200
                                }
                        }	
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");
			return;
		}
	}	
        
        /* Send Measurement Msg Task */ 
	task void sendMyTask()
	{
                uint8_t mlen,mynode_measurement,mask;
                error_t sendDone;
                Measurement* payl;
                message_t tmp;
                uint16_t mdest;
                uint16_t countRes;
                uint16_t maxRes;
                float minLim =0;
                float maxLim=0;
                bool countChanged =FALSE;
                bool maxChanged = FALSE;
                bool countOp= FALSE;
                bool maxOp = FALSE;
                Measurement* mypkt;
                TwoMeasurements* mypkt2;
       
                if(call MySendQueue.empty())
                {
                        dbg("SRTreeC","MySendQueue is empty\n");               
                }  
                
                // Deque the message containing the value
                radioMySendPkt = call MySendQueue.dequeue();
                
                mlen = call MyPacket.payloadLength(&radioMySendPkt);               
                payl = call MyPacket.getPayload(&radioMySendPkt,mlen);
                
                // Valid Package size
                if(mlen != sizeof(Measurement))
                {
                        dbg("SRTreeC","sendMyTask(): Unkwown message \n"); 
                        return;              
                }              
                
                // Valid operation
                if(!(operation == MAX || operation == COUNT || operation == BOTH)){
                        // dbg("SRTreeC","sendMyTask(): No Operation Specified \n"); 
                        return;
                }

                // flags to determine operations done
                if(operation == COUNT){
                        // dbg("SRTreeC","sendMyTask(): No Operation COUNT \n"); 
                        countOp = TRUE;
                }
                else if(operation == MAX){
                        // dbg("SRTreeC","sendMyTask(): No Operation MAX \n"); 
                        maxOp = TRUE;
                }
                else {
                        // dbg("SRTreeC","sendMyTask(): No Operation Both \n"); 
                        countOp = TRUE;
                        maxOp = TRUE;
                }

                // dbg("SRTreeC","sendMyTask(): COUNT AFTER :  %d\t MAX AFTER: %d\n",countOp,maxOp); 


                mynode_measurement = payl->measurement;

                // Calculations Section
                if(countOp)
                {
                        countRes = count_calculation();
                        if(countRes > 127 ){
                                countRes= 127;
                        }
                        // dbg("SRTreeC","Calculate Count\n");
                        minLim = (1-((float) tct /100))*prevCount;
                        maxLim = (1+((float) tct /100))*prevCount;

                        if((countRes > maxLim) || (countRes < minLim )){
                                dbg("SRTreeC","The new Count value is ACCEPTED.\n");
                                countChanged = TRUE;
                        }
                        else{
                                countChanged = FALSE;
                                dbg("SRTreeC","The new Count value is REJECTED.\n"); 
                        }
                        dbg("SRTreeC","Tct: %d\t  Previous Count: %d\t New Count: %d\t Reject-Range:[%f,%f]\n",tct, prevCount,countRes,minLim,maxLim); 
                }
                if(maxOp)
                {        
                        maxRes = max_calculation(mynode_measurement);
                        if(maxRes > 127 ){
                                maxRes= 127;
                        }
                        // dbg("SRTreeC","Calculate Max \n");
                        minLim = (1-((float) tct /100))*prevMax;
                        maxLim = (1+((float) tct /100))*prevMax;
                        if((maxRes > maxLim) || (maxRes < minLim )){
                                dbg("SRTreeC","The new Max value is ACCEPTED.\n");
                                maxChanged = TRUE;
                        }
                        else{
                                dbg("SRTreeC","The new Max value is REJECTED.\n");
                                maxChanged = FALSE;
                        }
                        dbg("SRTreeC","Tct: %d\t  Previous Max: %d\t New Max: %d\t Reject-Range:[%f,%f]\n",tct, prevMax,maxRes,minLim,maxLim); 
                }

                // Send Section
                if(countChanged && maxChanged){
                        dbg("SRTreeC","SendMyTask(): Send Both\n");
                        call MyPacket.setPayloadLength(&tmp , sizeof(TwoMeasurements));
                        mypkt2 = (TwoMeasurements *)(call MyPacket.getPayload(&tmp , sizeof(TwoMeasurements)));
                        
                        // Verify valid payload 
                        if(mypkt2 == NULL)
                        {
                                dbg("SRTreeC","sendMyTask(): No valid payload \n"); 
                                return;              
                        }
                        
                        call MyAMPacket.setDestination(&tmp,parentID);
                        
                        ((TwoMeasurements*) mypkt2)->count = countRes;
                        ((TwoMeasurements*) mypkt2)->max = maxRes;
                        
                        memcpy(&radioMySendPkt,&tmp,sizeof(message_t));

                        mdest = call MyAMPacket.destination(&radioMySendPkt);
                        mlen  = call MyPacket.payloadLength(&radioMySendPkt);
                        // dbg("SRTreeC","SendMyTask(): =============================================Send LEN: %d\n", mlen); 
                        
                        sendDone = call MyAMSend.send(mdest,&radioMySendPkt, mlen);      
                        dbg("SRTreeC", "SEND DONE %s \n",(sendDone==SUCCESS)?"True":"False");
                }
                else if(countChanged && !maxChanged){
                        dbg("SRTreeC","SendMyTask(): Send Count Only\n");
                        call MyPacket.setPayloadLength(&tmp , sizeof(Measurement));
                        mypkt = (Measurement *)(call MyPacket.getPayload(&tmp , sizeof(Measurement)));
                        
                        // Verify valid payload 
                        if(mypkt == NULL)
                        {
                                dbg("SRTreeC","sendMyTask(): No valid payload \n"); 
                                return;              
                        }
                        call MyAMPacket.setDestination(&tmp,parentID);
                        
                        if(operation == BOTH){
                                mask = 0x7F;
                                // mask bit 0 with certainty
                                mypkt->measurement = (mask & countRes); 
                        }
                        else mypkt->measurement = countRes;

                        memcpy(&radioMySendPkt,&tmp,sizeof(message_t));
                        mdest = call MyAMPacket.destination(&radioMySendPkt);
                        mlen  = call MyPacket.payloadLength(&radioMySendPkt);
                        // dbg("SRTreeC","SendMyTask(): =============================================Send lEN: %d\n", mlen); 
                        
                        sendDone = call MyAMSend.send(mdest,&radioMySendPkt, mlen);
                        dbg("SRTreeC", "SEND DONE %s \n",(sendDone==SUCCESS)?"True":"False");            
                }
                else if(!countChanged && maxChanged){
                        dbg("SRTreeC","SendMyTask(): Send Max Only\n");

                        call MyPacket.setPayloadLength(&tmp , sizeof(Measurement));
                        mypkt = (Measurement *)(call MyPacket.getPayload(&tmp , sizeof(Measurement)));
                        
                        // Verify valid payload 
                        if(mypkt == NULL)
                        {
                                dbg("SRTreeC","sendMyTask(): No valid payload \n"); 
                                return;              
                        }

                        call MyAMPacket.setDestination(&tmp,parentID);
                        // We add mask
                        if(operation == BOTH){
                                mask = 0x80;
                                mypkt->measurement = (maxRes | mask);
                        }
                        else mypkt->measurement = maxRes;
                        memcpy(&radioMySendPkt,&tmp,sizeof(message_t));
                        mdest = call MyAMPacket.destination(&radioMySendPkt);
                        mlen  = call MyPacket.payloadLength(&radioMySendPkt);
                        sendDone = call MyAMSend.send(mdest,&radioMySendPkt, mlen);

                        dbg("SRTreeC", "SEND DONE %s \n",(sendDone==SUCCESS)?"True":"False");
                }

                // update previous Values
                if(countChanged)
                        prevCount = countRes;
                if(maxChanged)
                        prevMax = maxRes;
                // Final Output
                // Debug Printing From Root
                if (TOS_NODE_ID == 0)
                {
                        if(countOp){
                                dbg("SRTreeC","Final Result: Count = %d\n", prevCount);   
                        }
                        if(maxOp){
                                dbg("SRTreeC","Final Result: Max = %d\n",prevMax); 
                        }
                } 
                                 
        }
	 
	task void receiveMyTask()
	{
                // message_t tmp;
		uint8_t len,i;
		message_t radioMyRecPkt;
                uint16_t msource;
                Measurement* mypkt;
                TwoMeasurements* mypkt2;

		radioMyRecPkt= call MyReceiveQueue.dequeue();
		len = call MyPacket.payloadLength(&radioMyRecPkt);

		// dbg("SRTreeC","ReceiveMyTask(): len=%u \n",len);
                
                msource = call MyAMPacket.source(&radioMyRecPkt);
                if(operation == MAX)
		{
                        dbg("SRTreeC","========================================== MAX Received ==========================================\n");      
		        mypkt = (Measurement*) (call MyPacket.getPayload(&radioMyRecPkt,len));
                        for(i=0; i<NUM_MAX_CHILDREN; i++) {
                                if(array_children[i].childrenId == msource || array_children[i].childrenId ==0)
                                {
                                        if(array_children[i].childrenId == 0)
                                        {
                                                array_children[i].childrenId = msource;
                                        }
                                        array_children[i].max = mypkt->measurement;
                                        dbg("SRTreeC","Received from childId %d  - max %d \n",array_children[i].childrenId,array_children[i].max);
                                        break;
                                }
                        }
                }
                else if(operation == COUNT)
                {        
                        dbg("SRTreeC","========================================== Count Received ==========================================\n");      
                        mypkt = (Measurement*) (call MyPacket.getPayload(&radioMyRecPkt,len));
                        for(i=0; i<NUM_MAX_CHILDREN; i++) {
                                if(array_children[i].childrenId == msource || array_children[i].childrenId ==0)
                                {
                                        if(array_children[i].childrenId ==0)
                                        {
                                                array_children[i].childrenId=msource;
                                        }
                                        array_children[i].count = mypkt->measurement;
                                        dbg("SRTreeC","Received from childId %d  - count %d \n",array_children[i].childrenId,array_children[i].count);
                                        break;
                                }
                        }
                }
                else if(operation == BOTH)
                {
                        // dbg("SRTreeC","===============================================================LEN = %d \t sizeof(TwoMeasurement) = %d\n",len ,sizeof(TwoMeasurements));
                        if(len == sizeof(TwoMeasurements)){
                                dbg("SRTreeC","========================================== Max & Count Received ==========================================\n");      
                                mypkt2 = (TwoMeasurements*) (call MyPacket.getPayload(&radioMyRecPkt,len));
                                for(i=0; i<NUM_MAX_CHILDREN; i++) {          
                                        if(array_children[i].childrenId == msource || array_children[i].childrenId ==0)
                                        {
                                                if(array_children[i].childrenId ==0)
                                                {
                                                        array_children[i].childrenId=msource;
                                                }
                                                array_children[i].count = mypkt2->count;
                                                array_children[i].max = mypkt2->max;
                                                dbg("SRTreeC","Count & Max: Received from childId %d  - Count %d -Max %d \n",array_children[i].childrenId,array_children[i].count,array_children[i].max);
                                                break;
                                        }
                                }
                        }
                        else{
                                mypkt = (Measurement*) (call MyPacket.getPayload(&radioMyRecPkt,len));
                                if((0x80 & mypkt->measurement) == 0x00){ // only count sent
                                        dbg("SRTreeC","========================================== Only Count Received ==========================================\n");      
                                        for(i=0; i<NUM_MAX_CHILDREN; i++) {
                                                if(array_children[i].childrenId == msource || array_children[i].childrenId ==0)
                                                {
                                                        if(array_children[i].childrenId ==0)
                                                        {
                                                                array_children[i].childrenId=msource;
                                                        }
                                                        array_children[i].count =  mypkt->measurement;
                                                        dbg("SRTreeC","Received from childId %d  - count %d \n",array_children[i].childrenId,array_children[i].count);
                                                        break;
                                                }
                                        }
                                }
                                else{
                                        dbg("SRTreeC","========================================== Only Max Received ==========================================\n");
                                        for(i=0; i<NUM_MAX_CHILDREN; i++) {
                                                if(array_children[i].childrenId == msource || array_children[i].childrenId ==0)
                                                {
                                                        if(array_children[i].childrenId == 0)
                                                        {
                                                                array_children[i].childrenId = msource;
                                                        }
                                                        array_children[i].max = mypkt->measurement & 0x7F;
                                                        dbg("SRTreeC","Received from childId %d  - max %d \n",array_children[i].childrenId,array_children[i].max);
                                                        break;
                                                }
                                         }
                                }
                        }
                }	
	}

        task void sendOpTask()
	{
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
	        if (call OpSendQueue.empty())
		{
			dbg("SRTreeC","sendOpTask(): Q is empty!\n");
			return;
		}
		
		if(OpSendBusy)
		{
			dbg("SRTreeC","sendOpTask(): OpSendBusy= TRUE!!!\n");
			return;
		}

                //dequeue to minima apo tin oura
		radioOpSendPkt = call OpSendQueue.dequeue();
		mlen= call OpPacket.payloadLength(&radioOpSendPkt);
		mdest=call OpAMPacket.destination(&radioOpSendPkt);

		if(mlen!=sizeof(OpMsg))
		{
			dbg("SRTreeC","sendOpTask(): Unknown message!!!\n");
			return;
		}
		sendDone=call OpAMSend.send(mdest,&radioOpSendPkt,mlen);
		
		if (sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendOpTask(): Send returned success!!!\n");
		}
		else
		{
			dbg("SRTreeC","sendOpTask(): send failed!!!\n");
		}
	}
	
        /* Receive Op Msg Task */ 
        task void receiveOpTask()
	{
                // message_t tmp;
		uint8_t len;
		message_t radioOpRecPkt;
                uint16_t msource;
                uint32_t rand_time;


		radioOpRecPkt= call OpReceiveQueue.dequeue();
		len = call OpPacket.payloadLength(&radioOpRecPkt);

		// dbg("SRTreeC","ReceiveOpTask(): len=%u \n",len);
                msource = call OpAMPacket.source(&radioOpRecPkt);
                // If not routed before there is no reason not to start operating now
                // As it received the Change Op Broadcast
                if((parentID<0)||(parentID>=65535)){
                        return;
                }

                if(len == sizeof(OpMsg))
		{
                        if(!op_changed)
                        {
                                OpMsg * mpkt = (OpMsg*) (call OpPacket.getPayload(&radioOpRecPkt,len));
                                operation = mpkt->operation;
                                // dbg("SRTreeC","Operation Updated\n");

                                if (TOS_NODE_ID!=0)
                                {
                                        // rand_time = (call Random.rand16())%(ROUTING_TIME);
                                        op_changed = TRUE;
                                        call UpdateOpTimer.startOneShot(TIMER_FAST_PERIOD*2);  // To send by depth
                                }
                        }
		}
		else
		{
			dbg("SRTreeC","receiveOpTask():Empty message!!! \n");
			return;
		}
        
	}
}



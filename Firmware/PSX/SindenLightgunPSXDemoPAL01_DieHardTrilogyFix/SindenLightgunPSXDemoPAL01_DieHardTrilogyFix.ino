#include <SPI.h>

// -------------------------------
// PSX pin mapping
// -------------------------------
#define IN_CMD MOSI
#define OUT_DATA MISO
#define OUT_ACK 7
#define IN_ATT SS
#define IN_CLK SCK

// -------------------------------
// Local test buttons (active-low to GND)
// -------------------------------
#define TestButtonTrigger 5
#define TestButtonA 255     // DISABLED in this sketch (D4 used by pedal)
#define TestButtonB 3

// -------------------------------
// Pedal (Option A off-screen reload) - wired to D4
// -------------------------------
#define PedalReloadPin 4    // Pedal to GND when pressed (INPUT_PULLUP)

// -------------------------------
#define DATA_SIZE 8

uint8_t ReadMask[DATA_SIZE]   = { 0xFF, 0xFF, 0, 0, 0, 0, 0, 0 };
uint8_t ReadExpect[DATA_SIZE] = { 0x01, 0x42, 0, 0, 0, 0, 0, 0 };

// GunCon reply template
volatile uint8_t Reply[DATA_SIZE] = { 0x63, 0x5A, 0xFF, 0xFF, 0x01, 0x00, 0x05, 0x00 };

volatile uint8_t DataIndex = 0;
volatile bool bDataGood = true;

#define ReadAttention() (PINB&(1<<2))
#define WriteAckLow() (DDRD|=(1<<7))
#define WriteAckHigh() (DDRD&=~(1<<7))
#define DelayMicro() asm("NOP\nNOP\nNOP\nNOP\nNOP\nNOP\nNOP\nNOP\n")

int testButtonStateTrigger = HIGH;
int testButtonStateA = HIGH;
int testButtonStateB = HIGH;

// -------------------------------
// START COMBO SUPPORT
// Hold A+B+Trigger for 1000ms -> arm START
// Then tap Trigger -> send START once (latched for a couple polls)
// -------------------------------
volatile bool gStartArmed = false;
volatile uint8_t gStartLatch = 0; // polls to hold START "pressed"
unsigned long gComboStartMs = 0;
bool gLastTrigPressed = false;

// Persist last serial button bytes
volatile uint8_t gLastSerialButtons1 = 0;
volatile uint8_t gLastSerialButtons2 = 0;

// -------------------------------
// PEDAL OFFSCREEN RELOAD (Option A)
// -------------------------------
volatile uint8_t gReloadLatch = 0;
static bool gLastPedalPressed = false;

ISR (SPI_STC_vect)
{
  uint8_t DataIn = SPDR;

  if (DataIndex < DATA_SIZE)
  {
    bDataGood &= ((DataIn & ReadMask[DataIndex]) == ReadExpect[DataIndex]);

    uint8_t outByte = Reply[DataIndex];

    // ---- START handling (byte 3, bit 3 = 0x08, active-low) ----
    if (DataIndex == 3)
    {
      if (gStartLatch == 0)
        outByte |= 0x08;     // START released
      else
        outByte &= ~0x08;    // START pressed
    }

    if (bDataGood)
    {
      SPDR = outByte;

      WriteAckLow();
      DelayMicro(); DelayMicro(); DelayMicro(); DelayMicro();
      WriteAckHigh();
    }
    else
    {
      SPDR = 0xFF;
    }

    DataIndex++;
  }
  else
  {
    SPDR = 0xFF;
  }
}

void setup()
{
  pinMode(OUT_ACK, INPUT);
  digitalWrite(OUT_ACK, 0);

  pinMode(MISO, OUTPUT);

  // Enable SPI in Slave mode, LSB first, MODE3 (CPOL=1, CPHA=1)
  SPCR |= bit(SPE) | bit(DORD) | bit(CPOL) | bit(CPHA);
  SPI.attachInterrupt();

  pinMode(TestButtonTrigger, INPUT_PULLUP);
  if (TestButtonA != 255) pinMode(TestButtonA, INPUT_PULLUP);
  pinMode(TestButtonB, INPUT_PULLUP);

  pinMode(PedalReloadPin, INPUT_PULLUP);

  Serial.begin(57600);
  while (!Serial) { }
}

void loop()
{
  
  // firmware_mode query
  if (Serial.available() > 0)
  {
      int incoming = Serial.peek();  // look without consuming

      // If it's not your binary packet start byte, treat as command
      if (incoming != 222)
      {
          incoming = Serial.read();

          if (incoming == 'I')   // e.g. send 'I' for identify
          {
              Serial.println("KONAMI-PAL");
          }
          return; // don't process as gun data
      }
  }

  // Only update Reply[] when ATT is high (idle)
  if (ReadAttention() != 0)
  {
    // End of a transaction: reset state and tick down latches once per poll
    if (DataIndex != 0)
    {
      DataIndex = 0;
      bDataGood = true;

      if (gStartLatch > 0) gStartLatch--;
      if (gReloadLatch > 0) gReloadLatch--;
    }

    // Read local test buttons (active-low)
    testButtonStateTrigger = digitalRead(TestButtonTrigger);
    testButtonStateA = (TestButtonA != 255) ? digitalRead(TestButtonA) : HIGH;
    testButtonStateB = digitalRead(TestButtonB);

    // Pedal (active-low): edge detect to start reload latch
    bool pedalPressed = (digitalRead(PedalReloadPin) == LOW);
    if (pedalPressed && !gLastPedalPressed)
    {
      gReloadLatch = 2;   // set to 1 if you want a shorter tap
    }
    gLastPedalPressed = pedalPressed;

    // Handle serial packet if available
    if (Serial.available() > 5)
    {
      int StartByte = Serial.read();
      int SerialX = Serial.read();
      int SerialY = Serial.read();
      int SerialButtonsValue1 = Serial.read();
      int SerialButtonsValue2 = Serial.read();
      int EndByte = Serial.read();

      if (StartByte != 222 || EndByte != 223)
      {
        int LookingForEnd = 0;
        while (LookingForEnd != 223)
        {
          if (Serial.available() > 0)
            LookingForEnd = Serial.read();
        }
        return;
      }

      // Persist latest serial button bytes
      gLastSerialButtons1 = (uint8_t)SerialButtonsValue1;
      gLastSerialButtons2 = (uint8_t)SerialButtonsValue2;

      // Echo as your original code does
      Serial.write(SerialButtonsValue1);

      // -------------------------------
      // SAFE OFFSCREEN HANDLING (base coordinates)
      // -------------------------------
      if (SerialX < 3 || SerialX > 252 || SerialY < 3 || SerialY > 252)
      {
        Reply[4] = 0x00;
        Reply[5] = 0x00;
        Reply[6] = 0x00;
        Reply[7] = 0x00;
      }
      else
      {
        float percentx = (float)SerialX / 255;
        float percenty = (float)SerialY / 255;

        float positionx = percentx * (461 - 77) + 77;
        float positiony = percenty * (295 - 32) + 32;

        int posx = (int)positionx;
        int posy = (int)positiony;

        if (posx > 255)
        {
          Reply[4] = posx - 255;
          Reply[5] = 0x01;
        }
        else
        {
          Reply[4] = posx;
          Reply[5] = 0x00;
        }

        if (posy > 255)
        {
          Reply[6] = posy - 255;
          Reply[7] = 0x01;
        }
        else
        {
          Reply[6] = posy;
          Reply[7] = 0x00;
        }
      }

      // -------------------------------
      // BUTTON HANDLING
      // -------------------------------
      Reply[2] = 0xFF;
      Reply[3] = 0xFF;

      bool trigPressed = ((gLastSerialButtons1 & 1) != 0) || (testButtonStateTrigger == LOW);

      bool aPressed =
        ((gLastSerialButtons1 & 2) != 0) ||
        ((gLastSerialButtons1 & 4) != 0) ||
        ((gLastSerialButtons1 & 32) != 0) ||
        (testButtonStateA == LOW);

      bool bPressed =
        ((gLastSerialButtons1 & 8) != 0) ||
        ((gLastSerialButtons1 & 16) != 0) ||
        (testButtonStateB == LOW);

      if (bPressed) Reply[3] &= ~0x40;   // B
      if (aPressed) Reply[2] &= ~0x08;   // A
      if (trigPressed) Reply[3] &= ~0x20; // Trigger

      // -------------------------------
      // START COMBO
      // -------------------------------
      if (aPressed && bPressed && trigPressed)
      {
        if (gComboStartMs == 0) gComboStartMs = millis();
        if (!gStartArmed && (millis() - gComboStartMs) >= 1000UL)
          gStartArmed = true;
      }
      else
      {
        gComboStartMs = 0;
      }

      bool trigRising = (trigPressed && !gLastTrigPressed);
      if (gStartArmed && trigRising)
      {
        gStartLatch = 2;
        gStartArmed = false;
      }
      gLastTrigPressed = trigPressed;

      if (gStartLatch == 0) Reply[3] |= 0x08;
      else Reply[3] &= ~0x08;

      // -------------------------------
      // PEDAL OFFSCREEN RELOAD (Die Hard Trilogy)
      // Force coords to X=511, Y=511 (definitely offscreen), and press trigger
      // -------------------------------
      if (gReloadLatch > 0)
      {
        Reply[4] = 0xFF; Reply[5] = 0x01;   // X = 511
        Reply[6] = 0xFF; Reply[7] = 0x01;   // Y = 511
        Reply[3] &= ~0x20;                  // Trigger pressed
      }
    }
    else
    {
      // No new serial packet: still enforce START state
      if (gStartLatch == 0) Reply[3] |= 0x08;
      else Reply[3] &= ~0x08;

      // Pedal reload even without serial updates
      if (gReloadLatch > 0)
      {
        Reply[4] = 0xFF; Reply[5] = 0x01;
        Reply[6] = 0xFF; Reply[7] = 0x01;
        Reply[3] &= ~0x20;
      }
    }
  }
}
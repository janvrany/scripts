#include "h1.h"
#include "h2.h"

#if (H1 != 0) && (H2 != 0)
# error "Both H1 and H2 non-zero"
#endif

int main(int argc, char **argv) {
    return H1 + H2;
}

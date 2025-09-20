//
// Created by daen on 20.09.25.
//

#ifndef DYSTOPIAN_CRYPTO_SAFE_INPUT_H
#define DYSTOPIAN_CRYPTO_SAFE_INPUT_H
#include <iostream>
#include <ostream>

#include "safe_input.h"
#include "../namespace.h"

DL_BASE_NAMESPACE_BEGIN
    void SafeInput::with_unsecure_input() const {
    std::cout << "Safe Input" << std::endl;
};

DL_BASE_NAMESPACE_END

#endif //DYSTOPIAN_CRYPTO_SAFE_INPUT_H